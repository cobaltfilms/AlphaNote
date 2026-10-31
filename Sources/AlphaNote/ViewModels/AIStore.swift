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
        // Une note sécurisée ne sort jamais de l'appareil, même la demande.
        guard !note.isVault else {
            noteStore.aiStatusMessage = "Note sécurisée : la barre de commande et l'IA n'y ont pas accès."
            return
        }

        noteStore.isAIProcessing = true
        defer { noteStore.isAIProcessing = false }

        let decision = await routing.route(question: trimmed, noteKeyword: note.keyword)
        noteStore.lastRoute = decision
        noteStore.aiStatusMessage = await apply(decision: decision, question: trimmed, to: note)
    }

    private func apply(decision: ModeDecision, question: String, to note: Note) async -> String {
        let via = "Mode \(decision.mode.label) via \(decision.source.label)"
        let detail: String
        switch decision.mode {
        case .math:
            detail = await applyMath(question: question, to: note)
        case .list:
            detail = await applyList(question: question, to: note)
        case .timer:
            detail = applyTimer(question: question)
        case .code:
            detail = applyCode(to: note)
        case .plain, .vault:
            detail = "Aucun mode appliqué."
        }

        var message = "\(via) — \(detail)"
        if decision.source == .motsCles, let echec = decision.echec {
            message += " (JEV : \(echec))"
        }
        return message
    }

    /// Ordre : expression déjà écrite → conversion → formule rédigée par
    /// l'IA (seule exception au contrat JEV) → dernier recours déterministe.
    private func applyMath(question: String, to note: Note) async -> String {
        if let expression = strictExpression(from: question) {
            writeMathBlock("\(expression) =", to: note)
            return "Expression notée, résultat calculé par la note."
        }

        if converter.convert(question) != nil {
            let expression = conversionExpressionCandidate(from: question)
            writeMathBlock(expression, to: note)
            return "Conversion notée."
        }

        var draftFailure: String?
        if FormulaDraftFeature.isEnabled, FormulaDraftFeature.hasDrafter {
            switch await FormulaDraftFeature().draft(question: question) {
            case let .ok(draft):
                let origin = draft.model.map { "IA (\($0))" } ?? "IA"
                let header = "// \(String(question.prefix(80))) — formule proposée par l'\(origin), à vérifier"
                writeMathBlock(([header] + draft.lines).joined(separator: "\n"), to: note)
                return "Formule rédigée par l'\(origin) et calculée par la note — vérifie-la."
            case let .erreur(message):
                draftFailure = message
            }
        }

        if let expression = numericFragment(from: question) {
            writeMathBlock("\(expression) =", to: note)
            return "Expression notée, résultat calculé par la note." + (draftFailure.map { " (\($0))" } ?? "")
        }

        return "Aucune expression évaluable trouvée — note inchangée." + (draftFailure.map { " (\($0))" } ?? "")
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

    private func applyList(question: String, to note: Note) async -> String {
        if let url = URLDetector.extractURLs(from: question).first {
            return await applyRecipe(url: url, to: note)
        }

        let items = Self.listItems(from: question)
        var updated = note

        if !items.isEmpty {
            let body = items.map { "* \($0)" }.joined(separator: "\n")
            if updated.keyword == "list", !Self.existingListBody(note).isEmpty {
                updated.content = Self.ensureListHeader(note) + "\n" + body
            } else {
                updated.content = "list: \(Self.listTitle(from: question))\n\(body)"
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

    /// Ingrédients lus dans les données structurées de la page (schema.org),
    /// sans IA. Une page sans recette structurée laisse la note intacte.
    private func applyRecipe(url: URL, to note: Note) async -> String {
        let host = url.host?.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression) ?? url.absoluteString
        switch await RecipeIngredientExtractor.fetch(url) {
        case let .success(recipe):
            let body = recipe.ingredients.map { "* \($0)" }.joined(separator: "\n")
            var updated = note
            let title = recipe.title ?? "Recette"
            // Source en fin de liste : l'aperçu de la note montre les ingrédients.
            let block = "list: \(title)\n\(body)\n// \(url.absoluteString)"
            if updated.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || updated.keyword == "list" {
                updated.content = block
            } else {
                updated.content = "\(block)\n\n\(updated.content)"
            }
            updated.content = ListModeFormatter.normalizeForListMode(content: updated.content, forceListHeader: true)
            updated.detectKeyword()
            noteStore.updateNote(updated)
            return "\(recipe.ingredients.count) ingrédient(s) lus sur \(host)."
        case let .failure(failure):
            return "Recette illisible sur \(host) : \(failure.message) — note inchangée."
        }
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

        // Note vide (ouverte pour la demande) : elle devient le minuteur, au
        // lieu d'en créer une autre et de laisser une note vide derrière.
        if let current = currentNote, current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var updated = current
            updated.content = content
            noteStore.updateNote(updated)
            return "\(label) créé."
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

    nonisolated static func listItems(from text: String) -> [String] {
        let raw = text
            // « … à mes courses », « … dans la liste » : la destination, pas un élément.
            .replacingOccurrences(of: #"(?i)\s+(à|a|dans|sur|pour)\s+(ma|mes|la|le|les|notre|nos|une?)\s+(liste|checklist|todo|to-do|courses)\b.*$"#,
                                  with: "", options: .regularExpression)
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

    /// Titre générique, comme Android : la demande entière ferait un titre bavard.
    nonisolated static func listTitle(from question: String) -> String {
        let lower = question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if lower.contains("course") { return "Courses" }
        if lower.contains("ingredient") { return "Ingrédients" }
        if lower.contains("tache") || lower.contains("todo") { return "Tâches" }
        return "Liste"
    }

    nonisolated static func existingListBody(_ note: Note) -> String {
        note.content.components(separatedBy: .newlines).dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// La note entière (en-tête compris) : les nouveaux éléments s'ajoutent à
    /// la suite, ils ne remplacent pas la liste existante.
    nonisolated static func ensureListHeader(_ note: Note) -> String {
        let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = content.components(separatedBy: .newlines).first ?? ""
        return ListModeFormatter.isListHeader(first) ? content : "list\n\(content)"
    }

    /// La demande, débarrassée des mots d'appel, est déjà une expression
    /// complète : aucun mot inconnu (l'évaluateur les ignorerait en silence,
    /// « aire d'un cercle de rayon 3 » donnerait 3).
    private func strictExpression(from question: String) -> String? {
        let stripped = question
            .replacingOccurrences(of: #"(?i)\b(calcule|calcul|combien|resultat|résultat|donne|fait|font)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty,
              stripped.rangeOfCharacter(from: .decimalDigits) != nil,
              mathEvaluator.evaluate(stripped) != nil else { return nil }
        let words = stripped
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "_")).inverted)
            .filter { $0.first?.isLetter == true || $0.first == "_" }
        // « of » fait partie de la syntaxe de l'évaluateur (« 50% of 200 »).
        guard words.allSatisfy({ MathEvaluator.isKnownName($0) || $0.lowercased() == "of" }) else { return nil }
        return stripped
    }

    /// Dernier recours sans IA : le premier fragment purement numérique qui
    /// contient un opérateur (« 12*8 stp » → « 12*8 »).
    private func numericFragment(from question: String) -> String? {
        guard let range = question.range(of: #"[0-9\(][0-9\(\)\+\-\*\/\^\.\,\s]*[0-9\)]"#, options: .regularExpression) else {
            return nil
        }
        let expression = String(question[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard expression.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^")) != nil,
              mathEvaluator.evaluate(expression) != nil else { return nil }
        return expression
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
