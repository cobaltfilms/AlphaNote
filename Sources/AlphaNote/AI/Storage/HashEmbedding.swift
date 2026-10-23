import Foundation

/// Embedding déterministe « sac de mots haché » : 64 dimensions, hachage
/// FNV-1a stable d'un lancement à l'autre (contrairement à `hashValue`, dont
/// la graine change à chaque processus — ce qui rendait les vecteurs
/// persistés inutilisables à la relance).
enum HashEmbedding {
    static let dimensions = 64
    static let modelID = "fnv64-v2"

    static func embed(text: String) -> [Double] {
        var vector = Array(repeating: 0.0, count: dimensions)
        let tokens = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        guard !tokens.isEmpty else { return vector }

        for token in tokens {
            let bucket = Int(fnv1a64(token) % UInt64(dimensions))
            vector[bucket] += 1
        }

        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    static func fnv1a64<S: StringProtocol>(_ string: S) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0, lnorm = 0.0, rnorm = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lnorm += lhs[index] * lhs[index]
            rnorm += rhs[index] * rhs[index]
        }
        guard lnorm > 0, rnorm > 0 else { return 0 }
        return dot / (sqrt(lnorm) * sqrt(rnorm))
    }
}
