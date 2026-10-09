import Foundation

/// Recherche sémantique locale : embeddings déterministes (hash-64) stockés
/// dans SQLite, similarité cosinus + score lexical. Aucun modèle, aucun
/// réseau — elle fonctionne même JEV hors-ligne.
struct SemanticSearchFeature {
    func index(note: Note) async {
        await EmbeddingStore.shared.upsertEmbedding(for: note)
    }

    func search(query: String, notes: [Note], topK: Int = 5) async -> [SemanticSearchHit] {
        await VectorIndex.shared.search(query: query, notes: notes, topK: topK)
    }
}
