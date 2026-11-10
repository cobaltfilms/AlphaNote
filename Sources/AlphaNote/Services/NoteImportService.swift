import Foundation

struct NoteImportReport {
    let source: String
    let scanned: Int
    let imported: Int
    let skippedDuplicates: Int
    let skippedEmpty: Int
    let failed: Int
    /// Notes déjà importées, complétées par ce passage (dossier → thème, date d'origine).
    var updated: Int = 0
    /// Notes de la corbeille de la source, laissées de côté.
    var skippedTrashed: Int = 0

    var summary: String {
        if scanned == 0 {
            return "\(source) : aucune note trouvée."
        }
        var parts = ["\(imported) importée(s) sur \(scanned)"]
        if updated > 0 { parts.append("\(updated) déjà là, complétée(s) (thème, date)") }
        if skippedDuplicates > 0 { parts.append("\(skippedDuplicates) doublon(s) ignoré(s)") }
        if skippedEmpty > 0 { parts.append("\(skippedEmpty) vide(s) ou verrouillée(s)") }
        if skippedTrashed > 0 { parts.append("\(skippedTrashed) dans la corbeille") }
        if failed > 0 { parts.append("\(failed) en échec") }
        return "\(source) : " + parts.joined(separator: ", ") + "."
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

    /// Importe Apple Notes en gardant ce qui range les notes : le dossier
    /// devient le thème, les dates d'origine sont conservées, la corbeille
    /// (« Suppressions récentes ») est laissée de côté. Relancer l'import
    /// complète les notes déjà importées sans les dupliquer.
    func importAppleNotes() throws -> NoteImportReport {
        let rawNotes = try fetchAppleNotesInBatches()
        let kept = rawNotes.filter { !Self.isTrashFolder($0.folder) }
        let entries: [ImportEntry] = kept.map(Self.entry(from:))

        var report = importEntries(entries, source: "Apple Notes")
        report.skippedTrashed = rawNotes.count - kept.count
        notifyNotesChanged()
        return report
    }

    /// Dossier « Suppressions récentes » d'Apple Notes, dans les langues courantes.
    static func isTrashFolder(_ folder: String?) -> Bool {
        guard let folder else { return false }
        return trashFolderKeys.contains(NoteThemes.key(folder))
    }

    private static let trashFolderKeys: Set<String> = Set([
        "Recently Deleted", "Suppressions récentes", "Supprimées récemment", "Onlangs verwijderd",
        "Zuletzt gelöscht", "Eliminados recientemente", "Eliminati di recente",
    ].map(NoteThemes.key))

    /// Dossier par défaut : il ne dit rien du sujet, la note reste sans thème écrit.
    private static let defaultFolderKeys: Set<String> = Set(["Notes", "Notities", "Notizen", "Notas", "Note"].map(NoteThemes.key))

    static func theme(fromFolder folder: String?) -> String? {
        guard let folder else { return nil }
        let name = NoteThemes.normalized(folder)
        guard !name.isEmpty, !defaultFolderKeys.contains(NoteThemes.key(name)) else { return nil }
        return name
    }

    private static func entry(from dto: AppleNoteDTO) -> ImportEntry {
        ImportEntry(
            title: (dto.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            content: dto.plaintext ?? "",
            theme: theme(fromFolder: dto.folder),
            createdAt: dto.created.flatMap(Self.isoDate),
            updatedAt: dto.modified.flatMap(Self.isoDate)
        )
    }

    private static func isoDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    func importEntries(_ entries: [ImportEntry], source: String) -> NoteImportReport {
        let existing = Note.fetchAllIncludingDeleted()
        // Une note déjà importée se reconnaît même après avoir reçu un thème.
        func key(of note: Note) -> String {
            dedupeKey(title: note.effectiveTitle, content: normalizeImportedText(NoteThemes.removingTheme(from: note.content)))
        }
        var dedupeSet = Set(existing.map(key(of:)))
        var liveByKey: [String: Note] = [:]
        for note in existing where !note.isDeleted && !note.isVault { liveByKey[key(of: note)] = note }
        var nextPosition = (existing.map(\.position).max() ?? -1) + 1

        var imported = 0
        var updated = 0
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
                if let live = liveByKey[key], complete(live, with: entry) {
                    updated += 1
                } else {
                    skippedDuplicates += 1
                }
                continue
            }

            var note = Note(position: nextPosition)
            // Titre laissé libre quand c'est déjà la première ligne : il suivra le texte.
            note.title = finalTitle == fallbackTitle(from: cleanedContent) ? "" : finalTitle
            note.content = NoteThemes.settingTheme(entry.theme, in: cleanedContent)
            note.detectKeyword()
            if let createdAt = entry.createdAt {
                note.createdAt = createdAt
                note.updatedAt = entry.updatedAt ?? createdAt
            }

            let created = Note.create(note, preservingDates: entry.createdAt != nil)
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
            failed: failed,
            updated: updated
        )
    }

    /// Complète une note importée par une version précédente : thème tiré du
    /// dossier si elle n'en a pas, date de création d'origine. Faux : rien à faire.
    private func complete(_ note: Note, with entry: ImportEntry) -> Bool {
        var completed = note
        if let theme = entry.theme, NoteThemes.explicit(in: note.content) == nil {
            completed.content = NoteThemes.settingTheme(theme, in: note.content)
        }
        if let createdAt = entry.createdAt, abs(note.createdAt.timeIntervalSince(createdAt)) > 86_400 {
            completed.createdAt = createdAt
        }
        guard completed != note else { return false }
        Note.update(completed)
        return true
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
                var folder = null;
                var created = null;
                var modified = null;
                try { title = String(n.name()); } catch (e) { title = ""; }
                try { plain = String(n.plaintext()); } catch (e) { plain = ""; }
                try { folder = String(n.container().name()); } catch (e) { folder = null; }
                try { created = n.creationDate().toISOString(); } catch (e) { created = null; }
                try { modified = n.modificationDate().toISOString(); } catch (e) { modified = null; }
                rows.push({
                    name: title,
                    plaintext: plain,
                    folder: folder,
                    created: created,
                    modified: modified
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

struct ImportEntry {
    let title: String
    let content: String
    var theme: String?
    var createdAt: Date?
    var updatedAt: Date?
}

private struct AppleNoteDTO: Decodable {
    let name: String?
    let plaintext: String?
    let folder: String?
    let created: String?
    let modified: String?
}

private struct AppleNotesBatchDTO: Decodable {
    let total: Int
    let offset: Int
    let notes: [AppleNoteDTO]
}
