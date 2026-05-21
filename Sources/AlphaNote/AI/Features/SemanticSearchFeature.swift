import Foundation

struct SemanticSearchFeature {
    private let remoteContext = RemoteContextFeature()

    func index(note: Note) async {
        await EmbeddingStore.shared.upsertEmbedding(for: note)
    }

    func search(query: String, notes: [Note], topK: Int = 5) async -> [SemanticSearchHit] {
        await VectorIndex.shared.search(query: query, notes: notes, topK: topK)
    }

    func answerCurrentNoteOnly(
        question: String,
        currentNote: Note,
        service: AIServiceProtocol = AIService.shared
    ) async throws -> AIResult {
        let currentTitle = currentNote.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = currentTitle.isEmpty ? "Note active" : currentTitle
        var contexts: [NoteContext] = [
            NoteContext(
                uuid: currentNote.uuid,
                title: "[NOTE ACTIVE PRIORITAIRE] \(displayTitle)",
                content: currentNote.content
            )
        ]
        let remote = await remoteContext.contexts(from: question, maxCount: 2)
        contexts.append(contentsOf: remote)

        let pseudoNote = Note(content: question)
        return try await service.run(
            task: .semanticAnswer,
            note: pseudoNote,
            context: AIContext(noteTitle: "", languageCode: "fr", relatedNotes: contexts)
        )
    }
}
