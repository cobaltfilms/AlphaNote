import Foundation

struct ActionItemsFeature {
    let service: AIServiceProtocol

    init(service: AIServiceProtocol = AIService.shared) {
        self.service = service
    }

    func run(note: Note) async throws -> AIResult {
        try await service.run(task: .extractActions, note: note, context: .empty)
    }
}
