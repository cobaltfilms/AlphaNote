import Foundation

struct SemanticSearchHit: Identifiable, Equatable {
    let id = UUID()
    let note: Note
    let score: Double
}

actor VectorIndex {
    static let shared = VectorIndex()

    func search(query: String, notes: [Note], topK: Int) async -> [SemanticSearchHit] {
        let queryVector = embed(text: query)
        let embeddings = await EmbeddingStore.shared.fetchAllEmbeddings()
        let byUUID = Dictionary(uniqueKeysWithValues: embeddings.map { ($0.noteUUID, $0.vector) })

        let scored: [SemanticSearchHit] = notes.compactMap { note in
            guard let vector = byUUID[note.uuid], !vector.isEmpty else {
                return nil
            }
            let lexical = lexicalScore(query: query, note: note)
            let semantic = cosineSimilarity(queryVector, vector)
            let score = (0.65 * semantic) + (0.35 * lexical)
            return SemanticSearchHit(note: note, score: score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(max(1, topK))
            .map { $0 }
    }

    private func embed(text: String) -> [Double] {
        var vector = Array(repeating: 0.0, count: 64)
        let tokens = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        for token in tokens {
            let bucket = abs(token.hashValue) % 64
            vector[bucket] += 1
        }
        let norm = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
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

    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }

        var dot = 0.0
        var lnorm = 0.0
        var rnorm = 0.0

        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lnorm += lhs[index] * lhs[index]
            rnorm += rhs[index] * rhs[index]
        }

        guard lnorm > 0, rnorm > 0 else { return 0 }
        return dot / (sqrt(lnorm) * sqrt(rnorm))
    }
}
