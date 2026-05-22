import Foundation

struct NoteImportReport {
    let source: String
    let scanned: Int
    let imported: Int
    let skippedDuplicates: Int
    let skippedEmpty: Int
    let failed: Int

    var summary: String {
        if scanned == 0 {
            return "\(source): no notes found in the selected source."
        }
        return "\(source): \(imported)/\(scanned) imported, \(skippedDuplicates) duplicates skipped, \(skippedEmpty) empty skipped, \(failed) failed."
    }
}

enum NoteImportError: LocalizedError {
    case invalidConfiguration(String)
    case commandFailed(String)
    case commandTimedOut
    case deniedAppleEvents
    case invalidAppleNotesPayload

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return message
        case let .commandFailed(message):
            return message
        case .commandTimedOut:
            return "Apple Notes import timed out. Try again after opening Apple Notes, then keep AlphaNote in foreground."
        case .deniedAppleEvents:
            return "Apple Notes access is not authorized. Allow automation for AlphaNote in macOS Privacy & Security > Automation, then retry."
        case .invalidAppleNotesPayload:
            return "Apple Notes returned an unexpected payload."
        }
    }
}

final class NoteImportService {
    static let shared = NoteImportService()

    private init() {}

    func importNextcloudNotes(
        serverURL: String,
        username: String,
        password: String,
        folderPath: String
    ) async throws -> NoteImportReport {
        let cleanedServer = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedFolder = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedServer.isEmpty else {
            throw NoteImportError.invalidConfiguration("Nextcloud server URL is missing.")
        }
        guard !cleanedUsername.isEmpty else {
            throw NoteImportError.invalidConfiguration("Nextcloud username is missing.")
        }
        guard !cleanedPassword.isEmpty else {
            throw NoteImportError.invalidConfiguration("Nextcloud app password is missing.")
        }
        guard !cleanedFolder.isEmpty else {
            throw NoteImportError.invalidConfiguration("Nextcloud notes folder is missing.")
        }

        let client = try NextcloudWebDAVClient(
            serverURL: cleanedServer,
            username: cleanedUsername,
            password: cleanedPassword
        )
        let remoteFiles = try await client.listTextFiles(relativeFolderPath: cleanedFolder, recursive: true)

        let entries: [ImportEntry] = remoteFiles.map { file in
            ImportEntry(
                title: titleFromPath(file.path),
                content: normalizeImportedText(file.content)
            )
        }

        let report = importEntries(entries, source: "Nextcloud Notes")
        notifyNotesChanged()
        return report
    }

    func importAppleNotes() throws -> NoteImportReport {
        let rawNotes = try fetchAppleNotesInBatches()
        let entries: [ImportEntry] = rawNotes.map { dto in
            let plain = dto.plaintext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ImportEntry(
                title: (dto.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                content: normalizeImportedText(plain)
            )
        }

        let report = importEntries(entries, source: "Apple Notes")
        notifyNotesChanged()
        return report
    }

    private func importEntries(_ entries: [ImportEntry], source: String) -> NoteImportReport {
        let existing = Note.fetchAllIncludingDeleted()
        var dedupeSet = Set(existing.map { dedupeKey(title: $0.effectiveTitle, content: normalizeImportedText($0.content)) })
        var nextPosition = (existing.map(\.position).max() ?? -1) + 1

        var imported = 0
        var skippedDuplicates = 0
        var skippedEmpty = 0
        var failed = 0

        for entry in entries {
            let cleanedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedContent = normalizeImportedText(entry.content)
            if cleanedTitle.isEmpty && cleanedContent.isEmpty {
                skippedEmpty += 1
                continue
            }
            if cleanedContent.isEmpty {
                skippedEmpty += 1
                continue
            }

            let finalTitle = cleanedTitle.isEmpty ? fallbackTitle(from: cleanedContent) : cleanedTitle
            let key = dedupeKey(title: finalTitle, content: cleanedContent)
            if dedupeSet.contains(key) {
                skippedDuplicates += 1
                continue
            }

            var note = Note(position: nextPosition)
            note.title = finalTitle
            note.content = cleanedContent
            note.detectKeyword()

            let created = Note.create(note)
            if created.id == nil {
                failed += 1
                continue
            }

            dedupeSet.insert(key)
            nextPosition += 1
            imported += 1
        }

        return NoteImportReport(
            source: source,
            scanned: entries.count,
            imported: imported,
            skippedDuplicates: skippedDuplicates,
            skippedEmpty: skippedEmpty,
            failed: failed
        )
    }

    private func notifyNotesChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .alphaNoteDidSync, object: nil)
            SyncEngine.shared.notifyLocalChange()
        }
    }

    private func dedupeKey(title: String, content: String) -> String {
        let normalizedTitle = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = content
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedTitle)|\(normalizedContent)"
    }

    private func titleFromPath(_ path: String) -> String {
        let clean = (path as NSString).lastPathComponent
        let base = (clean as NSString).deletingPathExtension
        let humanized = base.replacingOccurrences(of: "_", with: " ")
        return humanized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fallbackTitle(from content: String) -> String {
        if let firstNonEmpty = content
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return String(firstNonEmpty.prefix(80))
        }
        return "Imported note"
    }

    private func normalizeImportedText(_ text: String) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        let lines = normalizedNewlines
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchAppleNotesInBatches() throws -> [AppleNoteDTO] {
        var offset = 0
        let batchSize = 20
        var collected: [AppleNoteDTO] = []
        var expectedTotal: Int?
        var guardLoopCount = 0

        while true {
            let batch: AppleNotesBatchDTO
            do {
                batch = try runAppleNotesBatch(offset: offset, limit: batchSize)
            } catch let noteError as NoteImportError {
                switch noteError {
                case .commandTimedOut:
                    throw NoteImportError.commandFailed("Apple Notes batch timed out at offset \(offset).")
                default:
                    throw noteError
                }
            } catch {
                throw NoteImportError.commandFailed("Apple Notes batch failed at offset \(offset): \(error.localizedDescription)")
            }
            if batch.offset != offset {
                throw NoteImportError.commandFailed("Apple Notes returned an unexpected batch offset.")
            }
            if expectedTotal == nil {
                expectedTotal = max(0, batch.total)
            }

            if batch.notes.isEmpty {
                break
            }

            collected.append(contentsOf: batch.notes)
            offset += batch.notes.count
            guardLoopCount += 1

            if let expectedTotal, offset >= expectedTotal {
                break
            }

            if guardLoopCount > 2_000 {
                throw NoteImportError.commandFailed("Apple Notes import aborted due to too many batches.")
            }
        }

        return collected
    }

    private func runAppleNotesBatch(offset: Int, limit: Int) throws -> AppleNotesBatchDTO {
        let script = """
        function run(argv) {
            var offset = parseInt(argv[0], 10);
            if (isNaN(offset) || offset < 0) offset = 0;
            var limit = parseInt(argv[1], 10);
            if (isNaN(limit) || limit < 1) limit = 120;

            var notesApp = Application("Notes");
            var notes = notesApp.notes();
            var total = notes.length;
            var end = offset + limit;
            if (end > total) end = total;

            var rows = [];
            for (var i = offset; i < end; i++) {
                var n = notes[i];
                var title = "";
                var plain = "";
                try { title = String(n.name()); } catch (e) { title = ""; }
                try { plain = String(n.plaintext()); } catch (e) { plain = ""; }
                rows.push({
                    name: title,
                    plaintext: plain
                });
            }
            return JSON.stringify({
                total: total,
                offset: offset,
                notes: rows
            });
        }
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script, "\(offset)", "\(limit)"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var outputData = Data()
        var errorData = Data()
        let dataLock = NSLock()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            dataLock.lock()
            outputData.append(chunk)
            dataLock.unlock()
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            dataLock.lock()
            errorData.append(chunk)
            dataLock.unlock()
        }

        try process.run()
        let timeoutSeconds: TimeInterval = 60
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw NoteImportError.commandTimedOut
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        let outputTail = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorTail = errorPipe.fileHandleForReading.readDataToEndOfFile()
        dataLock.lock()
        outputData.append(outputTail)
        errorData.append(errorTail)
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        dataLock.unlock()

        guard process.terminationStatus == 0 else {
            let lower = errorText.lowercased()
            if errorText.contains("-1743") || lower.contains("not authorized to send apple events") {
                throw NoteImportError.deniedAppleEvents
            }
            throw NoteImportError.commandFailed(errorText.isEmpty ? "Apple Notes export failed." : errorText)
        }

        guard !output.isEmpty else {
            throw NoteImportError.invalidAppleNotesPayload
        }

        guard let data = output.data(using: .utf8) else {
            throw NoteImportError.invalidAppleNotesPayload
        }
        let decoder = JSONDecoder()
        return try decoder.decode(AppleNotesBatchDTO.self, from: data)
    }
}

private struct ImportEntry {
    let title: String
    let content: String
}

private struct AppleNoteDTO: Decodable {
    let name: String?
    let plaintext: String?
}

private struct AppleNotesBatchDTO: Decodable {
    let total: Int
    let offset: Int
    let notes: [AppleNoteDTO]
}
