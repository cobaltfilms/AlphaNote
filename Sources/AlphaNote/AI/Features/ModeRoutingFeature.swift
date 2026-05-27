import Foundation

struct ModeRoutingFeature {
    enum RouteMode: String, CaseIterable, Hashable, Sendable {
        case math
        case list
        case web
        case qa
        case transform
        case timer
    }

    let service: AIServiceProtocol

    init(service: AIServiceProtocol = AIService.shared) {
        self.service = service
    }

    func routeModes(question: String, noteKeyword: String?) async -> Set<RouteMode> {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            let pseudoNote = Note(content: trimmed)
            let context = AIContext(
                noteTitle: noteKeyword ?? "",
                languageCode: "fr",
                relatedNotes: []
            )
            let result = try await service.run(task: .modeRouting, note: pseudoNote, context: context)
            let rawModes = (result.metadata["modes"] ?? "")
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

            var set = Set<RouteMode>()
            for raw in rawModes {
                if let mode = RouteMode(rawValue: raw) {
                    set.insert(mode)
                }
            }
            return set
        } catch {
            return []
        }
    }
}
