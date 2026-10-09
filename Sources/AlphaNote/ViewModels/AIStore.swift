import Foundation
import SwiftUI

/// Gère le routage de mode (JEV) et la recherche sémantique.
/// L'IA ne rédige jamais : elle classe, et le code local applique
/// déterministement le mode choisi. Chaque décision porte sa source
/// (JEV ou mots-clés) — c'est ce que l'écran affiche.
@MainActor
final class AIStore {
    private unowned let noteStore: NoteStore
    private let routing = ModeRoutingFeature()
    private let mathEvaluator = MathEvaluator()
    private let converter = Converter()

    init(noteStore: NoteStore) {
        self.noteStore = noteStore
    }

    private var notes: [Note] {
        get { noteStore.notes }
        set { noteStore.notes = newValue }
    }

    private var archivedNotes: [Note] {
        get { noteStore.archivedNotes }
        set { noteStore.archivedNotes = newValue }
    }

    private var currentNote: Note? {
        noteStore.currentNote
    }

    // MARK: - Routage de mode

    func routeQuestion(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let note = currentNote else {
            noteStore.aiStatusMessage = "Aucune note courante sélectionnée."
            return
        }

        noteStore.isAIProcessing = true
        defer { noteStore.isAIProcessing = false }

        let decision = await routing.route(question: trimmed, noteKeyword: note.keyword)
        noteStore.lastRoute = decision
        noteStore.aiStatusMessage = apply(decision: decision, question: trimmed, to: note)
    }

    private func apply(decision: ModeDecision, question: String, to note: Note) -> String {
        let via = "Mode \(decision.mode.label) via \(decision.source.label)"
        let detail: String
        switch decision.mode {
        case .math:
            detail = applyMath(question: question, to: note)
        case .list:
            detail = applyList(question: question, to: note)
        case .timer:
            detail = applyTimer(question: question)
        case .code:
            detail = applyCode(to: note)
        case .plain:
            detail = "Aucun mode appliqué."
        }

        var message = "\(via) — \(detail)"
        if decision.source == .motsCles, let echec = decision.echec {
            message += " (JEV : \(echec))"
        }
        return message
    }

    private func applyMath(question: String, to note: Note) -> String {
        if converter.convert(question) != nil {
            let expression = conversionExpressionCandidate(from: question)
            writeMathBlock(expression, to: note)
            return "Conversion notée."
        }

        for expression in mathExpressionCandidates(from: question) {
            if mathEvaluator.evaluate(expression) != nil {
                writeMathBlock("\(expression) =", to: note)
                return "Expression notée, résultat calculé par la note."
            }
        }

        return "Aucune expression évaluable trouvée — note inchangée."
    }

    private func writeMathBlock(_ block: String, to note: Note) {
        var updated = note
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if updated.keyword == "math" {
            updated.content += "\n\(trimmed)"
        } else if updated.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.content = "math: Calcul\n\(trimmed)"
        } else {
            updated.content = "math: Calcul\n\(trimmed)\n\n\(updated.content)"
        }
        updated.detectKeyword()
        noteStore.updateNote(updated)
    }

    private func applyList(question: String, to note: Note) -> String {
        let items = listItems(from: question)
        var updated = note

        if !items.isEmpty {
            let body = items.map { "* \($0)" }.joined(separator: "\n")
            if updated.keyword == "list", !existingListBody(note).isEmpty {
                updated.content = ensureListHeader(note) + "\n" + body
            } else {
                updated.content = "list: \(listTitle(from: question))\n\(body)"
            }
            updated.content = ListModeFormatter.normalizeForListMode(content: updated.content, forceListHeader: true)
            updated.detectKeyword()
            noteStore.updateNote(updated)
            return "Liste écrite dans la note."
        }

        if updated.keyword == "list" {
            return "La note est déjà en liste."
        }

        let normalized = ListModeFormatter.normalizeForListMode(content: updated.content, forceListHeader: true)
        guard normalized != updated.content else {
            return "Rien à mettre en liste — note inchangée."
        }
        updated.content = normalized
        updated.detectKeyword()
        noteStore.updateNote(updated)
        return "Note convertie en liste."
    }

    private func applyTimer(question: String) -> String {
        guard let (timerType, totalSeconds) = KeywordIntentRouter.parseTimerRequest(question) else {
            return "Durée non reconnue — note inchangée."
        }

        let content: String
        let label: String
        switch timerType {
        case .countdown:
            let min = totalSeconds / 60
            let sec = totalSeconds % 60
            content = "timer\ncountdown \(min):\(String(format: "%02d", sec))"
            label = sec == 0 ? "Minuteur \(min) min" : "Minuteur \(min) min \(sec) sec"
        case .stopwatch:
            content = "timer\nstopwatch"
            label = "Chronomètre"
        case .pomodoro:
            let min = totalSeconds / 60
            content = "timer\npomodoro \(min):00"
            label = "Pomodoro \(min) min"
        }

        guard noteStore.createNote(keyword: "timer", content: content) else {
            return "Création impossible."
        }
        return "\(label) créé."
    }

    private func applyCode(to note: Note) -> String {
        var updated = note
        guard updated.keyword != "code" else {
            return "La note est déjà en code."
        }
        if updated.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.content = "code"
        } else {
            updated.content = "code\n\(updated.content)"
        }
        updated.detectKeyword()
        noteStore.updateNote(updated)
        return "Note convertie en code."
    }

    // MARK: - Recherche sémantique

    func semanticSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            noteStore.semanticSearchResults = []
            return
        }
        let allNotes = notes + archivedNotes
        noteStore.semanticSearchResults = await SemanticSearchFeature().search(query: trimmed, notes: allNotes, topK: 6)
    }

    // MARK: - Helpers déterministes

    private func listItems(from text: String) -> [String] {
        let raw = text
            .replacingOccurrences(of: #"[;|]+"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"\s+et\s+"#, with: ", ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(fais|cree|crée|donne|genere|génère|ajoute)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(liste|checklist|todo|to-do|courses)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = raw
            .components(separatedBy: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            }
            .filter { part in
                guard part.count >= 2 else { return false }
                let folded = part.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                if folded.hasPrefix("je veux") || folded.hasPrefix("stp") || folded.hasPrefix("svp") {
                    return false
                }
                return true
            }

        return Array(NSOrderedSet(array: parts)) as? [String] ?? parts
    }

    private func listTitle(from question: String) -> String {
        let cleaned = question
            .replacingOccurrences(of: #"(?i)^(fais|cree|crée|donne|genere|génère|ajoute)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^(une?\s+)?(liste|checklist|todo|to-do)\s*(de|des|du|d')?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleaned.isEmpty ? question : cleaned
        return String(title.prefix(60))
    }

    private func existingListBody(_ note: Note) -> String {
        let lines = note.content.components(separatedBy: .newlines)
        guard let first = lines.first, ListModeFormatter.isListHeader(first) else {
            return ""
        }
        return Array(lines.dropFirst())
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func ensureListHeader(_ note: Note) -> String {
        let lines = note.content.components(separatedBy: .newlines)
        if let first = lines.first, ListModeFormatter.isListHeader(first) {
            return first
        }
        return "list: \(note.effectiveTitle.isEmpty ? "Liste" : note.effectiveTitle)"
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

        if let range = stripped.range(of: #"[0-9\(\)\+\-\*\/\^\.\,\s]+"#, options: .regularExpression) {
            let expression = String(stripped[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !expression.isEmpty {
                candidates.append(expression)
            }
        }

        return Array(Set(candidates))
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
}
