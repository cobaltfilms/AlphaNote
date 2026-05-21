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
        additionalURLs: [URL] = [],
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
        let questionURLs = URLDetector.extractURLs(from: question)
        let mergedURLs = questionURLs + additionalURLs
        let remote = await remoteContext.contexts(from: mergedURLs, maxCount: 2)
        contexts.append(contentsOf: remote)
        if AIIntentDetector.isWebResearchRequest(question) {
            let web = await remoteContext.webResearchContexts(query: question, maxCount: 3)
            contexts.append(contentsOf: web)
        }
        contexts.append(alphaNoteCapabilitiesContext())

        let pseudoNote = Note(content: question)
        return try await service.run(
            task: .semanticAnswer,
            note: pseudoNote,
            context: AIContext(noteTitle: "", languageCode: "fr", relatedNotes: contexts)
        )
    }

    private func alphaNoteCapabilitiesContext() -> NoteContext {
        NoteContext(
            uuid: "alphanote-doc-capabilities",
            title: "[DOC APP] Capacités AlphaNote",
            content: """
            AlphaNote est une application de notes locales.
            Fonctions principales:
            - mode math: calculs, pourcentages, conversions (unités/devises)
            - mode list: création et raffinement de listes actionnables
            - mode code: snippets prêts à coller dans la note
            - mode timer: notes orientées sessions de temps
            L'assistant doit produire du contenu final pour la note, pas un raisonnement intermédiaire.
            """
        )
    }
}
