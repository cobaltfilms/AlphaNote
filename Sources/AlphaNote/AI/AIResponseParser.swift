import Foundation

enum AIResponseParser {
    private struct ActionPayload: Decodable {
        struct ActionItem: Decodable {
            let title: String
            let owner: String
            let deadline: String
            let priority: String
        }

        let actions: [ActionItem]
    }

    static func parse(_ raw: String, for task: AITask) throws -> AIResult {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw AIError.invalidOutput
        }

        switch task {
        case .extractActions:
            return parseActions(cleaned)
        default:
            return AIResult(text: cleaned, metadata: [:])
        }
    }

    private static func parseActions(_ raw: String) -> AIResult {
        if let data = raw.data(using: .utf8),
           let payload = try? JSONDecoder().decode(ActionPayload.self, from: data) {
            let lines = payload.actions.enumerated().map { index, item in
                let priority = item.priority.isEmpty ? "medium" : item.priority
                let owner = item.owner.isEmpty ? "non assigné" : item.owner
                let deadline = item.deadline.isEmpty ? "non définie" : item.deadline
                return "\(index + 1). [\(priority)] \(item.title) — owner: \(owner), échéance: \(deadline)"
            }

            let text = lines.isEmpty ? "Aucune action détectée." : lines.joined(separator: "\n")
            return AIResult(text: text, metadata: ["format": "json_actions"])
        }

        // Fallback robuste en texte brut si le JSON est imparfait.
        return AIResult(text: raw, metadata: ["format": "text_fallback"])
    }
}
