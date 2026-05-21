import Foundation
import SwiftUI

@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var archivedNotes: [Note] = []
    @Published var currentIndex: Int = 0
    @Published var isAIProcessing = false
    @Published var aiError: String?
    @Published var lastAIResult: AIResultEnvelope?
    @Published var semanticSearchResults: [SemanticSearchHit] = []

    @AppStorage("archivedNoteIDs") private var legacyArchivedNoteIDsStorage: String = "[]"
    @AppStorage("archivedIDsMigratedToDatabase") private var archivedIDsMigratedToDatabase: Bool = false
    @AppStorage(AISettingsKeys.enabled) private var aiEnabled = false

    private var currentAITask: Task<Void, Never>?

    var currentNote: Note? {
        guard !notes.isEmpty, currentIndex >= 0, currentIndex < notes.count else {
            return nil
        }
        return notes[currentIndex]
    }

    func loadNotes() {
        migrateLegacyArchiveIDsIfNeeded()
        reloadNotes()
        repairListNotesIfNeeded()
        Task {
            for note in notes where !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await SemanticSearchFeature().index(note: note)
            }
        }
    }

    func addNote() {
        let allPositions = (notes + archivedNotes).map(\.position)
        let position = (allPositions.max() ?? -1) + 1
        let created = Note.create(Note(position: position))
        guard let createdID = created.id else {
            reloadNotes()
            return
        }
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: createdID)
    }

    func selectNote(id: Int64) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        currentIndex = index
    }

    func isArchived(_ note: Note) -> Bool {
        note.archived
    }

    func archiveNote(_ note: Note) {
        var updated = note
        updated.archived = true
        updateNote(updated)
        let nextSelection = adjacentNoteID(forDeletedNoteID: note.id)
        reloadNotes(selecting: nextSelection)
    }

    func unarchiveNote(_ note: Note) {
        var updated = note
        updated.archived = false
        updateNote(updated)
        reloadNotes(selecting: note.id)
    }

    func duplicateNote(_ note: Note) {
        var duplicated = note
        duplicated.id = nil
        duplicated.uuid = UUID().uuidString.lowercased()
        duplicated.createdAt = Date()
        duplicated.updatedAt = Date()
        duplicated.archived = false
        duplicated.isDeleted = false
        duplicated.deletedAt = nil
        duplicated.lastSyncedAt = nil
        duplicated.lastModifiedByDeviceId = DeviceIdentity.currentDeviceID
        duplicated.aiSummary = ""
        duplicated.aiLastProcessedAt = nil
        let allPositions = (notes + archivedNotes).map(\.position)
        duplicated.position = (allPositions.max() ?? -1) + 1

        let created = Note.create(duplicated)
        guard let createdID = created.id else {
            reloadNotes()
            return
        }

        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: createdID)
    }

    func renameNote(_ note: Note, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = note
        let lines = updated.content.components(separatedBy: .newlines)
        let firstLine = lines.first ?? ""
        let remaining = Array(lines.dropFirst())

        if ListModeFormatter.isListHeader(firstLine) {
            updated.content = remaining.isEmpty
                ? "list: \(trimmed)"
                : (["list: \(trimmed)"] + remaining).joined(separator: "\n")
        } else if lines.isEmpty {
            updated.content = trimmed
        } else {
            updated.content = ([trimmed] + remaining).joined(separator: "\n")
        }

        updated.detectKeyword()
        updateNote(updated)
    }

    func convertCurrentNoteToList() {
        guard var note = currentNote else { return }
        let normalized = ListModeFormatter.normalizeForListMode(content: note.content, forceListHeader: true)
        guard normalized != note.content else { return }
        note.content = normalized
        note.detectKeyword()
        updateNote(note)
    }

    func updateNote(_ note: Note) {
        Note.update(note)
        var updated = note
        updated.detectKeyword()
        updated.lastModifiedByDeviceId = DeviceIdentity.currentDeviceID

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = updated
        }
        if let index = archivedNotes.firstIndex(where: { $0.id == note.id }) {
            archivedNotes[index] = updated
        }
        SyncEngine.shared.notifyLocalChange()

        Task {
            await SemanticSearchFeature().index(note: updated)
        }
    }

    func deleteNote(_ note: Note) {
        let nextSelection = adjacentNoteID(forDeletedNoteID: note.id)
        Note.delete(note)
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: nextSelection)
    }

    func deleteEmptyNotes() {
        let selectedID = currentNote?.id
        Note.deleteEmpty()
        reloadNotes(selecting: selectedID)
    }

    func navigateNext() {
        guard !notes.isEmpty else {
            addNote()
            return
        }

        if deleteCurrentNoteIfEmptyAndSelectAdjacent(preferPrevious: false) {
            return
        }

        if currentIndex < notes.count - 1 {
            currentIndex += 1
        } else {
            addNote()
        }
    }

    func navigatePrevious() {
        guard !notes.isEmpty else {
            addNote()
            return
        }

        if deleteCurrentNoteIfEmptyAndSelectAdjacent(preferPrevious: true) {
            return
        }

        if currentIndex > 0 {
            currentIndex -= 1
        }
    }

    func summarizeCurrentNote() async {
        await runAIForCurrent(task: .summarize)
    }

    func rewriteCurrentNote(style: RewriteStyle) async {
        await runAIForCurrent(task: .rewrite(style: style))
    }

    func extractActionsCurrentNote() async {
        await runAIForCurrent(task: .extractActions)
    }

    func cancelAIOperation() {
        currentAITask?.cancel()
        currentAITask = nil
        isAIProcessing = false
        aiError = AIError.cancelled.localizedDescription
    }

    func applyLastAIResult(mode: AIApplyMode) {
        guard let envelope = lastAIResult else { return }
        guard let index = notes.firstIndex(where: { $0.id == envelope.noteID }) else {
            return
        }

        var note = notes[index]
        switch mode {
        case .replace:
            note.content = envelope.result.text
        case .insertBelow:
            if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note.content = envelope.result.text
            } else {
                note.content += "\n\n\(envelope.result.text)"
            }
        }
        note.aiLastProcessedAt = Date()
        if envelope.task == .summarize {
            note.aiSummary = envelope.result.text
        }
        note.detectKeyword()
        updateNote(note)
        lastAIResult = nil
    }

    func clearLastAIResult() {
        lastAIResult = nil
    }

    func semanticSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            semanticSearchResults = []
            return
        }
        // Sidebar IA searches across all notes (active + archived).
        let allNotes = notes + archivedNotes
        let result = await SemanticSearchFeature().search(query: trimmed, notes: allNotes, topK: 6)
        semanticSearchResults = result
    }

    func askNotes(question: String) async -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Question vide." }
        guard let currentNote else {
            return "Aucune note courante sélectionnée."
        }
        do {
            let answer = try await SemanticSearchFeature().answerCurrentNoteOnly(
                question: trimmed,
                currentNote: currentNote
            )
            let shouldAutoApplyList = AIIntentDetector.isExplicitListRequest(trimmed) ||
                (currentNote.keyword == "list" && AIIntentDetector.isListRefinementRequest(trimmed))
            if shouldAutoApplyList {
                convertSemanticAnswerToListOnCurrentNote(
                    answer.text,
                    titleHint: trimmed,
                    refinementPrompt: trimmed
                )
                return "Liste mise à jour dans la note courante."
            }
            return answer.text
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func insertSemanticAnswerIntoCurrentNote(_ answer: String) {
        guard var note = currentNote else { return }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note.content = trimmed
        } else {
            note.content += "\n\n\(trimmed)"
        }
        note.aiLastProcessedAt = Date()
        note.detectKeyword()
        updateNote(note)
    }

    func replaceCurrentNoteWithSemanticAnswer(_ answer: String) {
        guard var note = currentNote else { return }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        note.content = trimmed
        note.aiLastProcessedAt = Date()
        note.detectKeyword()
        updateNote(note)
    }

    func convertSemanticAnswerToListOnCurrentNote(_ answer: String, titleHint: String?, refinementPrompt: String? = nil) {
        guard var note = currentNote else { return }
        var items = listItems(from: answer)
        guard !items.isEmpty else { return }

        let oldItems = existingListItems(note)
        if AIIntentDetector.asksForQuantityDetails(refinementPrompt ?? ""),
           looksLikeSameItems(oldItems, items),
           !items.contains(where: { hasQuantityMarker($0) }) {
            items = items.map { "\($0) — quantité à préciser" }
        }

        let cleanedHint = inferredListTitle(from: titleHint, answer: answer, currentNote: note)
        let currentTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if !currentTitle.isEmpty, note.keyword == "list", shouldKeepCurrentListTitle(currentTitle, inferred: cleanedHint) {
            title = currentTitle
        } else if !cleanedHint.isEmpty {
            title = cleanedHint
        } else {
            title = "Liste IA"
        }

        let body = items.joined(separator: "\n")
        let raw = "list: \(title)\n\(body)"
        note.content = ListModeFormatter.normalizeForListMode(content: raw, forceListHeader: true)
        note.aiLastProcessedAt = Date()
        note.detectKeyword()
        updateNote(note)
    }

    private func inferredListTitle(from question: String?, answer: String, currentNote: Note?) -> String {
        let rawQuestion = (question ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        if let currentNote, currentNote.keyword == "list" {
            let currentTitle = currentNote.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let foldedCurrent = currentTitle.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if !currentTitle.isEmpty && foldedCurrent != "liste ia" && foldedCurrent != "ingredients" {
                return currentTitle
            }
        }

        if let fromAnswer = recipeNameFromText(answer), !fromAnswer.isEmpty {
            return "Ingrédients du \(fromAnswer)"
        }

        // Try to extract a semantic topic after "de/du/d'" in the prompt.
        if let topic = topicFromQuestion(rawQuestion), !topic.isEmpty {
            return "Ingrédients \(topic)"
        }

        // Fallback: use the first descriptive line of answer if present.
        if let line = answer
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty && !$0.hasPrefix("*") }) {
            let lower = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if lower.contains("ingredient") {
                if let topic = topicFromQuestion(line), !topic.isEmpty {
                    return "Ingrédients \(topic)"
                }
                return "Ingrédients"
            }
        }

        let folded = rawQuestion.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if folded.contains("ingredient") {
            return "Ingrédients"
        }
        return ""
    }

    private func recipeNameFromText(_ text: String) -> String? {
        let lowered = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let patterns = [
            #"rougail\s+de\s+([a-zàâçéèêëîïôûùüÿñæœ\-\s]+)"#,
            #"recette\s+de\s+([a-zàâçéèêëîïôûùüÿñæœ\-\s]+)"#
        ]

        for pattern in patterns {
            if let range = lowered.range(of: pattern, options: .regularExpression) {
                let match = String(lowered[range])
                if pattern.contains("rougail") {
                    let suffix = match.replacingOccurrences(of: "rougail de ", with: "")
                    let cleaned = suffix
                        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        return "rougail de \(cleaned)"
                    }
                } else {
                    let suffix = match.replacingOccurrences(of: "recette de ", with: "")
                    let cleaned = suffix
                        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }
        }
        return nil
    }

    private func topicFromQuestion(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // URL case: derive from slug.
        if let url = URLDetector.extractURLs(from: cleaned).first {
            let slug = url.path
                .components(separatedBy: "/")
                .last(where: { !$0.isEmpty })?
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ") ?? ""
            let simplified = slug
                .replacingOccurrences(of: #"(?i)\brecette\b"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\bwpid\d+\b"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !simplified.isEmpty {
                return "du \(simplified)"
            }
        }

        let folded = cleaned.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let markers = [" de ", " du ", " d'"]
        for marker in markers {
            if let range = folded.range(of: marker, options: .backwards) {
                let offset = folded.distance(from: folded.startIndex, to: range.upperBound)
                let originalStart = cleaned.index(cleaned.startIndex, offsetBy: min(offset, cleaned.count))
                var suffix = String(cleaned[originalStart...])
                suffix = suffix
                    .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"[^\p{L}\p{N}\s\-']"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !suffix.isEmpty {
                    if marker == " du " {
                        return "du \(suffix)"
                    }
                    if marker == " d'" {
                        return "d'\(suffix)"
                    }
                    return "de \(suffix)"
                }
            }
        }
        return nil
    }

    private func shouldKeepCurrentListTitle(_ current: String, inferred: String) -> Bool {
        let currentFolded = current.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let inferredFolded = inferred.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if currentFolded == "liste ia" || currentFolded == "ingredients" || currentFolded == "ingredients de morue" {
            return false
        }
        if inferredFolded.contains("rougail"), !currentFolded.contains("rougail") {
            return false
        }
        return true
    }

    private func existingListItems(_ note: Note) -> [String] {
        let lines = note.content.components(separatedBy: .newlines)
        let body: [String]
        if let first = lines.first, ListModeFormatter.isListHeader(first) {
            body = Array(lines.dropFirst())
        } else {
            body = lines
        }
        return body
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func canonicalItem(_ item: String) -> String {
        let withoutQty = item.replacingOccurrences(
            of: #"\b\d+[.,]?\d*\s*(g|kg|ml|l|cl|cuill[eè]re?s?|c\.?\s*[àa]\s*caf[eé]|tasse?s?)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return withoutQty
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeSameItems(_ oldItems: [String], _ newItems: [String]) -> Bool {
        let oldSet = Set(oldItems.map(canonicalItem).filter { !$0.isEmpty })
        let newSet = Set(newItems.map(canonicalItem).filter { !$0.isEmpty })
        guard !oldSet.isEmpty, !newSet.isEmpty else { return false }
        let overlap = oldSet.intersection(newSet).count
        let ratio = Double(overlap) / Double(max(oldSet.count, newSet.count))
        return ratio >= 0.8
    }

    private func hasQuantityMarker(_ item: String) -> Bool {
        item.range(
            of: #"\b\d+[.,]?\d*\s*(g|kg|ml|l|cl|cuill[eè]re?s?|c\.?\s*[àa]\s*caf[eé]|tasse?s?)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func listItems(from text: String) -> [String] {
        let trimmedLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let bulletPrefixPattern = #"^\s*(?:[-*•]\s+|\d+[.)]\s+)"#
        let bulletLines = trimmedLines.filter {
            $0.range(of: bulletPrefixPattern, options: .regularExpression) != nil
        }
        let sourceLines = bulletLines.isEmpty ? trimmedLines : bulletLines

        var items: [String] = []
        var seen = Set<String>()
        let uuidRegex = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#

        for raw in sourceLines {
            var line = raw.replacingOccurrences(
                of: bulletPrefixPattern,
                with: "",
                options: .regularExpression
            )
            line = line.replacingOccurrences(of: #"^\[(.*?)\]$"#, with: "$1", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let lower = line.lowercased()
            if lower.hasPrefix("sources") || lower.contains("tokens-per-sec") || lower.hasPrefix("generation:") ||
                lower.hasPrefix("peak memory:") || lower.hasPrefix("prompt eval") || lower.hasPrefix("eval:") ||
                line == "==========" || line == "=========" {
                continue
            }
            if line.range(of: uuidRegex, options: .regularExpression) != nil {
                continue
            }
            if line.hasPrefix("http://") || line.hasPrefix("https://") {
                continue
            }
            if bulletLines.isEmpty,
               (lower.hasPrefix("voici ") || lower.contains("liste des ingredients") || lower.contains("liste d'ingredients")) {
                continue
            }

            if !seen.contains(lower) {
                items.append(line)
                seen.insert(lower)
            }
        }

        return items
    }

    private func runAIForCurrent(task: AITask) async {
        guard aiEnabled else {
            aiError = AIError.disabled.localizedDescription
            return
        }
        guard let note = currentNote, let noteID = note.id else {
            aiError = AIError.internalFailure("Note introuvable.").localizedDescription
            return
        }

        currentAITask?.cancel()
        isAIProcessing = true
        aiError = nil

        let taskStart = Date()
        let worker = Task {
            do {
                let result = try await AIService.shared.run(task: task, note: note, context: .empty)
                if Task.isCancelled {
                    throw AIError.cancelled
                }
                await AIMetricsLogger.shared.record(
                    task: task,
                    duration: Date().timeIntervalSince(taskStart),
                    engine: result.metadata["engine"] ?? "mlx",
                    success: true
                )

                await MainActor.run {
                    self.lastAIResult = AIResultEnvelope(noteID: noteID, task: task, result: result)
                    self.isAIProcessing = false
                }
            } catch {
                let mapped = (error as? AIError) ?? AIError.internalFailure(error.localizedDescription)
                await AIMetricsLogger.shared.record(
                    task: task,
                    duration: Date().timeIntervalSince(taskStart),
                    engine: "mlx",
                    success: false
                )
                await MainActor.run {
                    self.aiError = mapped.localizedDescription
                    self.isAIProcessing = false
                }
            }
        }

        currentAITask = worker
        await worker.value
        currentAITask = nil
    }

    func viewForNote(_ note: Note) -> AnyView {
        let noteBinding = binding(for: note)

        switch note.keyword {
        case "math":
            return AnyView(MathNoteView(note: noteBinding))
        case "list":
            return AnyView(ListNoteView(note: noteBinding))
        case "code":
            return AnyView(CodeNoteView(note: noteBinding))
        case "timer":
            return AnyView(TimerNoteView())
        default:
            return AnyView(PlainNoteView(note: noteBinding, store: self))
        }
    }

    private func binding(for note: Note) -> Binding<Note> {
        Binding(
            get: {
                guard let noteID = note.id,
                      let index = self.notes.firstIndex(where: { $0.id == noteID }) else {
                    return note
                }
                return self.notes[index]
            },
            set: { updatedNote in
                if let noteID = updatedNote.id,
                   let index = self.notes.firstIndex(where: { $0.id == noteID }) {
                    self.notes[index] = updatedNote
                } else if self.currentIndex >= 0 && self.currentIndex < self.notes.count {
                    self.notes[self.currentIndex] = updatedNote
                }

                self.updateNote(updatedNote)
            }
        )
    }

    private func reloadNotes(selecting selectedID: Int64? = nil) {
        let allNotes = Note.fetchAll()
        notes = allNotes.filter { !$0.archived }
        archivedNotes = allNotes.filter { $0.archived }

        if notes.isEmpty {
            let created = Note.create(Note(position: 0))
            notes = [created]
            currentIndex = 0
            return
        }

        if let selectedID,
           let index = notes.firstIndex(where: { $0.id == selectedID }) {
            currentIndex = index
            return
        }

        currentIndex = min(max(currentIndex, 0), notes.count - 1)
    }

    private var legacyArchivedNoteIDs: Set<Int64> {
        guard let data = legacyArchivedNoteIDsStorage.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int64].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    private func setLegacyArchivedNoteIDs(_ ids: Set<Int64>) {
        let sorted = ids.sorted()
        if let data = try? JSONEncoder().encode(sorted),
           let json = String(data: data, encoding: .utf8) {
            legacyArchivedNoteIDsStorage = json
        }
    }

    private func migrateLegacyArchiveIDsIfNeeded() {
        guard !archivedIDsMigratedToDatabase else { return }

        let archivedIDs = legacyArchivedNoteIDs
        guard !archivedIDs.isEmpty else {
            archivedIDsMigratedToDatabase = true
            return
        }

        let existing = Note.fetchAllIncludingDeleted()
        for var note in existing where archivedIDs.contains(note.id ?? -1) {
            if note.archived {
                continue
            }
            note.archived = true
            Note.update(note)
        }

        setLegacyArchivedNoteIDs([])
        archivedIDsMigratedToDatabase = true
    }

    private func repairListNotesIfNeeded() {
        let selectedID = currentNote?.id
        let candidates = notes + archivedNotes
        var changed = false

        for note in candidates where note.keyword == "list" {
            let normalized = ListModeFormatter.normalizeForListMode(content: note.content, forceListHeader: false)
            guard normalized != note.content else { continue }

            var updated = note
            updated.content = normalized
            updated.detectKeyword()
            Note.update(updated)
            changed = true
        }

        if changed {
            reloadNotes(selecting: selectedID)
        }
    }

    private func adjacentNoteID(forDeletedNoteID noteID: Int64?) -> Int64? {
        guard let noteID,
              let deletedIndex = notes.firstIndex(where: { $0.id == noteID }) else {
            return currentNote?.id
        }

        if deletedIndex + 1 < notes.count {
            return notes[deletedIndex + 1].id
        }

        if deletedIndex - 1 >= 0 {
            return notes[deletedIndex - 1].id
        }

        return nil
    }

    private func deleteCurrentNoteIfEmptyAndSelectAdjacent(preferPrevious: Bool) -> Bool {
        guard let current = currentNote else {
            return false
        }

        if !current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        let preferredID = preferPrevious
            ? notes[safe: currentIndex - 1]?.id
            : notes[safe: currentIndex + 1]?.id
        let fallbackID = preferPrevious
            ? notes[safe: currentIndex + 1]?.id
            : notes[safe: currentIndex - 1]?.id

        Note.delete(current)
        SyncEngine.shared.notifyLocalChange()
        reloadNotes(selecting: preferredID ?? fallbackID)
        return true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
