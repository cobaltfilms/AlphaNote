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

    private struct SemanticPayload: Decodable {
        struct Operation: Decodable {
            let type: String
            let content: String
            let title: String?
        }

        let answer: String
        let operation: Operation
        let sources: [String]
    }

    private struct ModeRoutingPayload: Decodable {
        let modes: [String]
        let confidence: Double?
        let reason: String?
    }

    static func parse(_ raw: String, for task: AITask) throws -> AIResult {
        let cleaned = sanitize(raw)
        guard !cleaned.isEmpty else {
            throw AIError.invalidOutput
        }

        switch task {
        case .extractActions:
            return parseActions(cleaned)
        case .modeRouting:
            return parseModeRouting(cleaned)
        case .semanticAnswer:
            return parseSemanticAnswer(cleaned)
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

    private static func parseSemanticAnswer(_ raw: String) -> AIResult {
        let normalizedJSON = stripCodeFence(raw)
        if let data = normalizedJSON.data(using: .utf8),
           let payload = try? JSONDecoder().decode(SemanticPayload.self, from: data) {
            let answer = payload.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            let operationType = payload.operation.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let operationContent = sanitize(payload.operation.content)
            let operationTitle = (payload.operation.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let sources = payload.sources.joined(separator: ",")
            let safeAnswer = answer.isEmpty ? operationContent : answer
            return AIResult(
                text: safeAnswer,
                metadata: [
                    "format": "json_semantic",
                    "operation_type": operationType,
                    "operation_content": operationContent,
                    "operation_title": operationTitle,
                    "sources": sources
                ]
            )
        }

        return AIResult(text: raw, metadata: ["format": "text_fallback"])
    }

    private static func parseModeRouting(_ raw: String) -> AIResult {
        let normalizedJSON = stripCodeFence(raw)
        if let data = normalizedJSON.data(using: .utf8),
           let payload = try? JSONDecoder().decode(ModeRoutingPayload.self, from: data) {
            let allowed = Set(["math", "list", "web", "qa", "transform"])
            let normalizedModes = payload.modes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { allowed.contains($0) }
            let uniqueModes = Array(NSOrderedSet(array: normalizedModes)) as? [String] ?? normalizedModes
            let confidence = payload.confidence.map { String($0) } ?? ""
            let reason = sanitize(payload.reason ?? "")

            return AIResult(
                text: reason,
                metadata: [
                    "format": "json_mode_routing",
                    "modes": uniqueModes.joined(separator: ","),
                    "confidence": confidence
                ]
            )
        }

        return AIResult(text: raw, metadata: ["format": "text_fallback"])
    }

    private static func sanitize(_ raw: String) -> String {
        var value = raw
        value = value.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: #"</?think>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripCodeFence(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
            return trimmed
        }

        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return trimmed }
        return lines
            .dropFirst()
            .dropLast()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
