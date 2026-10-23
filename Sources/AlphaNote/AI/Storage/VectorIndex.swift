import Foundation

struct SemanticSearchHit: Identifiable, Equatable {
    var id: String { note.uuid }
    let note: Note
    let score: Double
}

actor VectorIndex {
    static let shared = VectorIndex()

    func search(query: String, notes: [Note], topK: Int) async -> [SemanticSearchHit] {
        let queryVector = HashEmbedding.embed(text: query)
        let embeddings = await EmbeddingStore.shared.fetchAllEmbeddings()
        let byUUID = Dictionary(embeddings.map { ($0.noteUUID, $0.vector) }, uniquingKeysWith: { _, last in last })

        let scored: [SemanticSearchHit] = notes.compactMap { note in
            guard let vector = byUUID[note.uuid], !vector.isEmpty else { return nil }
            let lexical = lexicalScore(query: query, note: note)
            let semantic = HashEmbedding.cosineSimilarity(queryVector, vector)
            let score = (0.65 * semantic) + (0.35 * lexical)
            guard score > 0.05 else { return nil }
            return SemanticSearchHit(note: note, score: score)
        }

        return Array(scored.sorted { $0.score > $1.score }.prefix(max(1, topK)))
    }

    private func lexicalScore(query: String, note: Note) -> Double {
        let q = query.lowercased()
        let text = (note.effectiveTitle + "\n" + note.content).lowercased()
        guard !q.isEmpty else { return 0 }
        if text.contains(q) { return 1.0 }

        let tokens = q.split { !$0.isLetter && !$0.isNumber }
        guard !tokens.isEmpty else { return 0 }
        let matched = tokens.filter { text.contains($0) }.count
        return Double(matched) / Double(tokens.count)
    }
}
