import Foundation

struct RewriteFeature {
    let service: AIServiceProtocol

    init(service: AIServiceProtocol = AIService.shared) {
        self.service = service
    }

    func run(note: Note, style: RewriteStyle) async throws -> AIResult {
        try await service.run(task: .rewrite(style: style), note: note, context: .empty)
    }
}
