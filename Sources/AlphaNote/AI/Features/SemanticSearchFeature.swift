import Foundation

/// Recherche sémantique locale : embeddings déterministes (hash-64) stockés
/// dans SQLite, similarité cosinus + score lexical. Aucun modèle, aucun
/// réseau — elle fonctionne même JEV hors-ligne.
struct SemanticSearchFeature {
    /// Une note sécurisée n'est pas indexée, et perd l'index qu'elle avait
    /// avant de passer au coffre (il trahirait des mots du texte en clair).
    func index(note: Note) async {
        if note.isVault {
            await EmbeddingStore.shared.removeEmbedding(noteUUID: note.uuid)
        } else {
            await EmbeddingStore.shared.upsertEmbedding(for: note)
        }
    }

    func search(query: String, notes: [Note], topK: Int = 5) async -> [SemanticSearchHit] {
        await VectorIndex.shared.search(query: query, notes: notes.filter { !$0.isVault }, topK: topK)
    }
}
