import Foundation

enum AIIntentDetector {
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
        let normalized = question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return normalized.contains("quantite") ||
            normalized.contains("quantité") ||
            normalized.contains("gramme") ||
            normalized.contains("kg") ||
            normalized.contains("ml") ||
            normalized.contains("cuillere") ||
            normalized.contains("cuillère")
    }
}
