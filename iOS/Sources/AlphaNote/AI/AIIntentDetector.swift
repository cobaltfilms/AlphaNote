import Foundation

enum AIIntentDetector {
    enum NoteIntent: Sendable {
        case math
        case list
        case transform
        case webResearch
        case question
    }

    static func classifyIntent(_ question: String, noteKeyword: String?) -> NoteIntent {
        let isMathNote = (noteKeyword ?? "").lowercased() == "math"
        if isMathNote, isMathRequest(question, noteKeyword: noteKeyword) {
            return .math
        }

        let web = isWebResearchRequest(question)
        if web {
            return .webResearch
        }
        if isMathRequest(question, noteKeyword: noteKeyword) {
            return .math
        }
        if isListRequest(question, noteKeyword: noteKeyword) {
            return .list
        }
        if isNoteTransformationRequest(question) {
            return .transform
        }
        return .question
    }

    static func isWebResearchRequest(_ question: String) -> Bool {
        let query = normalized(question)
        let compact = compactNormalized(question)

        if !URLDetector.extractURLs(from: question).isEmpty {
            return true
        }

        let directMarkers = [
            "selon le web",
            "sur le web",
            "sur internet",
            "web",
            "internet",
            "recherche",
            "rechercher",
            "actualite",
            "actualité",
            "news",
            "cette semaine",
            "aujourd'hui",
            "a jour",
            "à jour",
            "recent",
            "récent"
        ]
        if directMarkers.contains(where: { query.contains($0) }) {
            return true
        }

        let typoMarkers = ["actu", "actualit", "internet", "web", "recen"]
        if typoMarkers.contains(where: { compact.contains($0) }) {
            return true
        }

        return false
    }

    static func isExplicitListRequest(_ question: String) -> Bool {
        let normalized = question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if normalized.contains("liste") {
            return true
        }

        let markers = [
            "fais une liste",
            "fais moi une liste",
            "donne moi une liste",
            "liste des ingredients",
            "liste d'ingredients",
            "ingredients",
            "checklist",
            "to-do list",
            "todo list"
        ]
        return markers.contains { normalized.contains($0) }
    }

    static func isListRefinementRequest(_ question: String) -> Bool {
        let normalized = question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let markers = [
            "ajoute",
            "complete",
            "ameliore",
            "améliore",
            "plus de details",
            "plus de détails",
            "quantite",
            "quantité",
            "precise",
            "précise",
            "detaille",
            "détaille"
        ]
        return markers.contains { normalized.contains($0) }
    }

    static func asksForQuantityDetails(_ question: String) -> Bool {
        let normalized = normalized(question)
        return normalized.contains("quantite") ||
            normalized.contains("quantité") ||
            normalized.contains("gramme") ||
            normalized.contains("kg") ||
            normalized.contains("ml") ||
            normalized.contains("cuillere") ||
            normalized.contains("cuillère")
    }

    static func isNoteTransformationRequest(_ question: String) -> Bool {
        let query = normalized(question)
        let markers = [
            "reecris", "réécris",
            "reformule", "reformuler",
            "corrige", "corriger",
            "ameliore", "améliore",
            "transforme", "transformer",
            "resume", "résume", "resume-moi",
            "traduis", "traduire",
            "mets en forme", "structure",
            "complete", "complète",
            "ajoute", "developpe", "développe",
            "genere", "génère",
            "fais une version"
        ]
        return markers.contains { query.contains($0) }
    }

    static func isMathRequest(_ question: String, noteKeyword: String?) -> Bool {
        let hasURL = !URLDetector.extractURLs(from: question).isEmpty
        let listLike = isListRequest(question, noteKeyword: noteKeyword)
        let isMathNote = (noteKeyword ?? "").lowercased() == "math"
        if hasURL && listLike && !isMathNote {
            return false
        }

        if isMathNote {
            return true
        }

        let query = normalized(question)
        let compact = compactNormalized(question)
        let markers = [
            "math",
            "calcule", "calcul", "combien",
            "pourcentage", "reduction", "réduction",
            "equation", "équation",
            "convertis", "conversion", "to ", " in ", " en "
        ]

        if markers.contains(where: { query.contains($0) }) {
            return true
        }

        let typoMathMarkers = [
            "pource", "pourcent", "poucent", "pourent",
            "reduc", "reduct", "remise", "promo",
            "prixbase", "prixfinal", "discount"
        ]
        if typoMathMarkers.contains(where: { compact.contains($0) }) {
            return true
        }

        if query.range(of: #"\d+\s*[\+\-\*\/\^]\s*\d+"#, options: .regularExpression) != nil {
            return true
        }

        // Price math heuristic: two numbers + pricing vocabulary.
        let hasTwoNumbers = numberCount(in: query) >= 2
        let hasPriceWords = query.contains("prix") || query.contains("coute") || query.contains("coûte") ||
            query.contains("vend") || query.contains("piece") || query.contains("pièce") ||
            query.contains("base") || query.contains("final")
        let hasCurrency = query.contains("€") || query.contains("$") || query.contains("eur") ||
            query.contains("usd") || query.contains("dh")
        if hasTwoNumbers && (hasPriceWords || hasCurrency) {
            return true
        }

        return false
    }

    static func isListRequest(_ question: String, noteKeyword: String?) -> Bool {
        if (noteKeyword ?? "").lowercased() == "list" {
            return true
        }

        if isExplicitListRequest(question) || isListRefinementRequest(question) {
            return true
        }

        let query = normalized(question)
        let compact = compactNormalized(question)

        let markers = [
            "todo", "to-do", "checklist", "liste", "courses",
            "ingredients", "ingrédients", "taches", "tâches"
        ]
        if markers.contains(where: { query.contains($0) }) {
            return true
        }

        let typoMarkers = ["ingred", "ingredient", "ingr", "list", "checklis", "todo"]
        if typoMarkers.contains(where: { compact.contains($0) }) {
            return true
        }

        // If user entered comma-separated tokens, this is likely list intent.
        let commaParts = question
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if commaParts.count >= 3 {
            return true
        }

        return false
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func compactNormalized(_ text: String) -> String {
        normalized(text)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
    }

    private static func numberCount(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"[-+]?\d+(?:[.,]\d+)?"#) else {
            return 0
        }
        return regex.numberOfMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
    }
}
