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
    private let mathEvaluator = MathEvaluator()
    private let converter = Converter()
    private let remoteContext = RemoteContextFeature()

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

        let modes = await resolveRouteModes(question: trimmed, currentNote: currentNote)
        let wantsWebResearch = modes.contains(.web)
        let wantsList = modes.contains(.list)
        let wantsMath = modes.contains(.math)
        let wantsTransform = modes.contains(.transform)
        let providedURLs = URLDetector.extractURLs(from: trimmed)

        if wantsMath && !wantsWebResearch,
           let localMathMessage = handleLocalMathRequest(question: trimmed, currentNote: currentNote) {
            return localMathMessage
        }

        if wantsList && !wantsWebResearch,
           let localListMessage = handleLocalListRequest(question: trimmed, currentNote: currentNote) {
            return localListMessage
        }

        if wantsWebResearch && wantsList && !providedURLs.isEmpty {
            let directIngredients = await remoteContext.recipeIngredientItems(from: trimmed, maxItems: 40)
            if !directIngredients.isEmpty {
                let payload = directIngredients.map { "* \($0)" }.joined(separator: "\n")
                convertSemanticAnswerToListOnCurrentNote(
                    payload,
                    titleHint: trimmed,
                    refinementPrompt: trimmed
                )
                return "Liste générée depuis l'URL fournie."
            }
        }

        do {
            let answer = try await SemanticSearchFeature().answerCurrentNoteOnly(
                question: trimmed,
                currentNote: currentNote
            )
            if let appliedMessage = applySemanticOperation(result: answer, question: trimmed) {
                return appliedMessage
            }

            let shouldAutoApplyList = !wantsWebResearch && (wantsList ||
                AIIntentDetector.isExplicitListRequest(trimmed) ||
                (currentNote.keyword == "list" && AIIntentDetector.isListRefinementRequest(trimmed)))
            if shouldAutoApplyList {
                let listPayload = semanticListPayload(from: answer)
                guard !listPayload.isEmpty else {
                    return "Je n'ai pas pu générer une liste propre. Donne 2-3 éléments clés et je la construis."
                }
                convertSemanticAnswerToListOnCurrentNote(
                    listPayload,
                    titleHint: trimmed,
                    refinementPrompt: trimmed
                )
                return "Liste mise à jour dans la note courante."
            }

            if wantsWebResearch {
                if wantsList {
                    let listPayload = semanticListPayload(from: answer)
                    if !listPayload.isEmpty {
                        convertSemanticAnswerToListOnCurrentNote(
                            listPayload,
                            titleHint: trimmed,
                            refinementPrompt: trimmed
                        )
                        return "Liste web générée dans la note courante."
                    }
                }

                let research = composedWebResearchText(from: answer)
                if !research.isEmpty {
                    replaceCurrentNoteWithSemanticAnswer(research)
                    return "Recherche web générée dans la note courante."
                }
                let fallback = cleanedSemanticFallbackText(answer.text)
                guard !fallback.isEmpty else {
                    return "Je n'ai pas trouvé de sources web exploitables pour cette demande."
                }
                replaceCurrentNoteWithSemanticAnswer(fallback)
                return "Réponse générée, mais sans sources web exploitables."
            }

            if wantsTransform {
                let cleaned = cleanedSemanticFallbackText(answer.text)
                guard !cleaned.isEmpty else {
                    return "Aucun résultat exploitable. Reformule avec une demande plus directe."
                }
                replaceCurrentNoteWithSemanticAnswer(cleaned)
                return "Note mise à jour automatiquement."
            }

            let cleaned = cleanedSemanticFallbackText(answer.text)
            if cleaned.isEmpty {
                return "Aucun résultat exploitable. Reformule avec une demande plus directe."
            }

            return cleaned
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

    private func applySemanticOperation(result: AIResult, question: String) -> String? {
        let operation = (result.metadata["operation_type"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let content = (result.metadata["operation_content"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (result.metadata["operation_title"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let responseText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch operation {
        case "replace":
            let payload = content.isEmpty ? responseText : content
            guard !payload.isEmpty else { return nil }
            replaceCurrentNoteWithSemanticAnswer(payload)
            return "Note mise à jour automatiquement."
        case "append":
            let payload = content.isEmpty ? responseText : content
            guard !payload.isEmpty else { return nil }
            insertSemanticAnswerIntoCurrentNote(payload)
            return "Contenu ajouté à la note."
        case "list":
            let payload = content.isEmpty ? responseText : content
            guard !payload.isEmpty else { return nil }
            convertSemanticAnswerToListOnCurrentNote(
                payload,
                titleHint: title.isEmpty ? question : title,
                refinementPrompt: question
            )
            return "Liste générée dans la note."
        case "none", "":
            return nil
        default:
            return nil
        }
    }

    private func cleanedSemanticFallbackText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        text = text.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</?think>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        let reasoningLinePatterns = [
            #"(?i)^okay[:,]?\s*the user"#,
            #"(?i)^okay[:,]?\s*let['’]s"#,
            #"(?i)^the user wants"#,
            #"(?i)^the question is"#,
            #"(?i)^let me "#,
            #"(?i)^i['’]?ll "#,
            #"(?i)^i will "#,
            #"(?i)^first[:,]?"#,
            #"(?i)^that makes sense"#,
            #"(?i)^so i need to"#,
            #"(?i)^i need to"#,
            #"(?i)^we need to"#,
            #"(?i)^je vais "#,
            #"(?i)^l['’]utilisateur"#,
            #"(?i)^réfléchissons"#,
            #"(?i)^pense"#,
            #"(?i)^je dois "#,
            #"(?i)^analysons"#,
            #"(?i)^analyse[:\s]"#
        ]

        let cleanedLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                for pattern in reasoningLinePatterns {
                    if line.range(of: pattern, options: .regularExpression) != nil {
                        return false
                    }
                }
                return true
            }

        let joined = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.isEmpty {
            return ""
        }
        if looksLikeReasoningMeta(joined) {
            return ""
        }
        return joined
    }

    private func looksLikeReasoningMeta(_ text: String) -> Bool {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let markers = [
            "the user", "the question is", "let's see", "i need to", "we need to",
            "l'utilisateur", "la question est", "je vais", "je dois", "raisonnement"
        ]
        let markerHits = markers.filter { normalized.contains($0) }.count
        if markerHits >= 2 {
            return true
        }
        return normalized.hasPrefix("okay") && normalized.contains("user")
    }

    private func semanticListPayload(from result: AIResult) -> String {
        let operationContent = (result.metadata["operation_content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let source = operationContent.isEmpty ? result.text : operationContent
        let cleaned = cleanedSemanticFallbackText(source)
        guard !cleaned.isEmpty else { return "" }
        let items = listItems(from: cleaned)
        guard !items.isEmpty else { return "" }
        return items.map { "* \($0)" }.joined(separator: "\n")
    }

    private func resolveRouteModes(question: String, currentNote: Note) async -> Set<ModeRoutingFeature.RouteMode> {
        let aiModes = await ModeRoutingFeature().routeModes(question: question, noteKeyword: currentNote.keyword)
        var modes = aiModes

        // Double filtering: deterministic safeguard layer.
        let hasURL = !URLDetector.extractURLs(from: question).isEmpty
        let heuristicMath = AIIntentDetector.isMathRequest(question, noteKeyword: currentNote.keyword)
        let heuristicList = AIIntentDetector.isListRequest(question, noteKeyword: currentNote.keyword)
        let heuristicWeb = AIIntentDetector.isWebResearchRequest(question)
        let heuristicTransform = AIIntentDetector.isNoteTransformationRequest(question)
        let isMathNote = currentNote.keyword.lowercased() == "math"

        if modes.isEmpty {
            if heuristicMath { modes.insert(.math) }
            if heuristicList { modes.insert(.list) }
            if heuristicWeb { modes.insert(.web) }
            if heuristicTransform { modes.insert(.transform) }
        }

        if heuristicWeb || hasURL {
            modes.insert(.web)
            modes.insert(.qa)
        }

        if heuristicList {
            modes.insert(.list)
        }

        if heuristicTransform {
            modes.insert(.transform)
        }

        if isMathNote {
            modes.insert(.math)
        } else if hasURL, modes.contains(.list), modes.contains(.web) {
            // New note + URL + list intent should not be hijacked by math.
            modes.remove(.math)
        }

        if modes.isEmpty {
            modes.insert(.qa)
        }

        return modes
    }

    private func composedWebResearchText(from result: AIResult) -> String {
        let base = cleanedSemanticFallbackText(result.text)
        var sections: [String] = []
        if !base.isEmpty {
            sections.append(base)
        }

        let sourceIDs = (result.metadata["sources"] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let urlSources = sourceIDs.compactMap { item -> String? in
            if item.hasPrefix("url:") {
                let encoded = String(item.dropFirst(4))
                return encoded.removingPercentEncoding ?? encoded
            }
            if item.hasPrefix("http://") || item.hasPrefix("https://") {
                return item
            }
            return nil
        }

        let answerURLs = URLDetector.extractURLs(from: base).map(\.absoluteString)
        let allSources = urlSources + answerURLs

        if !allSources.isEmpty {
            let unique = Array(NSOrderedSet(array: allSources)) as? [String] ?? allSources
            let formatted = unique.map { "- \($0)" }.joined(separator: "\n")
            sections.append("Sources:\n\(formatted)")
        }

        return sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleLocalListRequest(question: String, currentNote: Note) -> String? {
        guard AIIntentDetector.isListRequest(question, noteKeyword: currentNote.keyword) else {
            return nil
        }

        let directItems = localListItems(from: question)
        guard !directItems.isEmpty else {
            return nil
        }

        let payload = directItems.map { "* \($0)" }.joined(separator: "\n")
        convertSemanticAnswerToListOnCurrentNote(
            payload,
            titleHint: question,
            refinementPrompt: question
        )
        return "Liste générée dans la note courante."
    }

    private func localListItems(from question: String) -> [String] {
        let raw = question
            .replacingOccurrences(of: #"[;|]+"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"\s+et\s+"#, with: ", ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(fais|cree|crée|donne|genere|génère)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(liste|checklist|todo|to-do|ingredients|ingrédients)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = raw
            .components(separatedBy: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            }
            .filter { part in
                guard !part.isEmpty else { return false }
                let folded = part.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                if folded.count < 2 {
                    return false
                }
                if folded.hasPrefix("je veux") || folded.hasPrefix("stp") || folded.hasPrefix("svp") {
                    return false
                }
                return true
            }

        let unique = Array(NSOrderedSet(array: parts)) as? [String] ?? parts
        return unique
    }

    private func handleLocalMathRequest(question: String, currentNote: Note) -> String? {
        guard AIIntentDetector.isMathRequest(question, noteKeyword: currentNote.keyword) else {
            return nil
        }

        if let reduction = percentageReductionResult(question: question, noteContent: currentNote.content) {
            applyMathContentToCurrentNote(reduction.noteContent)
            return reduction.userMessage
        }

        if let pricing = pricingMathResult(question: question, noteContent: currentNote.content) {
            applyMathContentToCurrentNote(pricing.noteContent)
            return pricing.userMessage
        }

        if converter.convert(question) != nil {
            let conversionExpression = conversionExpressionCandidate(from: question)
            let mathNote = """
            math: Conversion IA
            \(conversionExpression)
            """
            applyMathContentToCurrentNote(mathNote)
            return "Conversion calculée et notée."
        }

        let candidates = mathExpressionCandidates(from: question)
        for expression in candidates {
            if let value = mathEvaluator.evaluate(expression) {
                let result = formattedMathNumber(value)
                let mathNote = """
                math: Calcul IA
                \(expression) =
                \(result)
                """
                applyMathContentToCurrentNote(mathNote)
                return "Calcul effectué et noté."
            }
        }

        return nil
    }

    private func percentageReductionResult(question: String, noteContent: String) -> (noteContent: String, userMessage: String)? {
        let normalized = question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let isReductionRequest = normalized.contains("pourcentage") &&
            (normalized.contains("reduction") || normalized.contains("réduction"))
        guard isReductionRequest else { return nil }

        let pair = resolvedPricePair(question: question, noteContent: noteContent)
        let basePrice = pair?.base ?? extractedNumbers(from: question).first
        let finalPrice = pair?.final ?? extractedNumbers(from: question).dropFirst().first

        guard let basePrice, let finalPrice else {
            let guide = """
            math: Réduction (%)
            // Remplace base et final avec tes valeurs
            base: 120
            final: 90
            reduction_pct: ((base - final) / base) * 100
            reduction_pct =
            """
            return (guide, "J'ai préparé la formule. Donne le prix de base et le prix final pour calculer le résultat.")
        }

        guard basePrice != 0 else {
            return ("", "Le prix de base ne peut pas être 0.")
        }

        let reduction = ((basePrice - finalPrice) / basePrice) * 100
        let mathNote = """
        math: Réduction (%)
        base: \(formattedMathNumber(basePrice))
        final: \(formattedMathNumber(finalPrice))
        reduction_pct: ((base - final) / base) * 100
        reduction_pct =
        """
        return (mathNote, "Réduction calculée: \(formattedMathNumber(reduction)) %")
    }

    private func pricingMathResult(question: String, noteContent: String) -> (noteContent: String, userMessage: String)? {
        let normalized = question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let hasPricingWords = normalized.contains("prix") || normalized.contains("vend") ||
            normalized.contains("piece") || normalized.contains("pièce") ||
            normalized.contains("euro") || normalized.contains("€") ||
            normalized.contains("achat") || normalized.contains("vente")
        guard hasPricingWords else { return nil }

        let pair = resolvedPricePair(question: question, noteContent: noteContent)
        let initial = pair?.base ?? extractedNumbers(from: question).first
        let final = pair?.final ?? extractedNumbers(from: question).dropFirst().first
        guard let initial, let final else { return nil }
        guard initial != 0 else { return nil }

        let amount = initial - final
        let pct = (amount / initial) * 100
        let mathNote = """
        math: Écart de prix
        prix_initial: \(formattedMathNumber(initial))
        prix_final: \(formattedMathNumber(final))
        reduction_montant: prix_initial - prix_final
        reduction_montant =
        reduction_pct: ((prix_initial - prix_final) / prix_initial) * 100
        reduction_pct =
        """
        return (
            mathNote,
            "Écart calculé: \(formattedMathNumber(amount)) et \(formattedMathNumber(pct)) % de réduction."
        )
    }

    private struct PriceMention {
        let value: Double
        let position: Int
        let hasCurrency: Bool
        let hasSellCue: Bool
        let hasBuyCue: Bool
        let hasPerUnitCue: Bool
        let hasNoiseCue: Bool

        var score: Int {
            var value = 0
            if hasCurrency { value += 4 }
            if hasSellCue { value += 3 }
            if hasBuyCue { value += 3 }
            if hasPerUnitCue { value += 1 }
            if hasNoiseCue { value -= 4 }
            return value
        }
    }

    private func resolvedPricePair(question: String, noteContent: String) -> (base: Double, final: Double)? {
        if let pair = resolvedPricePair(in: question) {
            return pair
        }
        let fallbackText = "\(question)\n\(noteContent)"
        return resolvedPricePair(in: fallbackText)
    }

    private func resolvedPricePair(in text: String) -> (base: Double, final: Double)? {
        let mentions = extractPriceMentions(from: text)
            .filter { $0.score >= 2 }
            .sorted { $0.position < $1.position }

        guard !mentions.isEmpty else { return nil }

        if let sell = mentions.first(where: { $0.hasSellCue }),
           let buy = mentions.first(where: { $0.hasBuyCue && $0.position > sell.position }) {
            return (sell.value, buy.value)
        }

        if let buy = mentions.first(where: { $0.hasBuyCue }),
           let sellBefore = mentions.last(where: { $0.hasSellCue && $0.position < buy.position }) {
            return (sellBefore.value, buy.value)
        }

        let currencyMentions = mentions.filter { $0.hasCurrency }
        if currencyMentions.count >= 2 {
            return (currencyMentions[0].value, currencyMentions[1].value)
        }

        if mentions.count >= 2 {
            return (mentions[0].value, mentions[1].value)
        }

        return nil
    }

    private func extractPriceMentions(from text: String) -> [PriceMention] {
        let pattern = #"(?:(?:€|\$|£|¥)\s*)?([-+]?\d+(?:[.,]\d+)?)(?:\s*(?:€|eur|usd|gbp|jpy|mad|dhs?|fcfa|\$|£|¥))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        var result: [PriceMention] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let numberRange = match.range(at: 1)
            guard numberRange.location != NSNotFound else { continue }

            let rawNumber = nsText.substring(with: numberRange).replacingOccurrences(of: ",", with: ".")
            guard let value = Double(rawNumber) else { continue }

            let matchText = nsText.substring(with: match.range)
            let hasCurrency = matchText.range(
                of: #"€|\$|£|¥|(?i)\beur\b|(?i)\busd\b|(?i)\bmad\b|(?i)\bdhs?\b|(?i)\bfcfa\b"#,
                options: .regularExpression
            ) != nil

            let contextStart = max(0, match.range.location - 26)
            let contextEnd = min(nsText.length, match.range.location + match.range.length + 26)
            let context = nsText.substring(with: NSRange(location: contextStart, length: contextEnd - contextStart))
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            let hasSellCue = containsAny(context, [
                " vend", " vente", " vendu", " prix", " tarif", " coute", "cout", "coûte"
            ])
            let hasBuyCue = containsAny(context, [
                " achet", " achat", " je veux", " payer", " paie", " propose", " nego", "nego", "negoc"
            ])
            let hasPerUnitCue = containsAny(context, [
                " piece", " pieces", " unite", " unites", "/u"
            ])
            let hasNoiseCue = containsAny(context, [
                " cheval", " chevaux", " cv", " kg", " km", " litre", " litres"
            ])

            result.append(
                PriceMention(
                    value: value,
                    position: match.range.location,
                    hasCurrency: hasCurrency,
                    hasSellCue: hasSellCue,
                    hasBuyCue: hasBuyCue,
                    hasPerUnitCue: hasPerUnitCue,
                    hasNoiseCue: hasNoiseCue
                )
            )
        }

        return result
    }

    private func containsAny(_ text: String, _ markers: [String]) -> Bool {
        markers.contains { text.contains($0) }
    }

    private func extractedNumbers(from text: String) -> [Double] {
        let pattern = #"[-+]?\d+(?:[.,]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            let raw = nsText.substring(with: match.range).replacingOccurrences(of: ",", with: ".")
            return Double(raw)
        }
    }

    private func mathExpressionCandidates(from question: String) -> [String] {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates = [trimmed]
        let stripped = trimmed
            .replacingOccurrences(of: #"(?i)\b(calcule|calcul|combien|resultat|résultat|donne)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stripped.isEmpty {
            candidates.append(stripped)
        }

        if let range = stripped.range(of: #"[0-9\(\)\+\-\*\/\^\.\,\%\s]+"#, options: .regularExpression) {
            let expression = String(stripped[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !expression.isEmpty {
                candidates.append(expression)
            }
        }

        return Array(Set(candidates))
    }

    private func applyMathContentToCurrentNote(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replaceCurrentNoteWithSemanticAnswer(trimmed)
    }

    private func conversionExpressionCandidate(from question: String) -> String {
        let pattern = #"[-+]?\d+(?:[.,]\d+)?\s*[a-zA-Z°"'\u00B2\u00B3]+\s*(?:to|in|en)\s*[a-zA-Z°"'\u00B2\u00B3]+"#
        if let range = question.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let expression = String(question[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !expression.isEmpty {
                return "\(expression) ="
            }
        }
        return "// Conversion\n\(question)"
    }

    private func formattedMathNumber(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int64(value))
        }

        var text = String(format: "%.6f", value)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
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
