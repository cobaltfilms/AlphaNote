import Foundation
import GRDB

struct EmbeddingRecord: FetchableRecord, MutablePersistableRecord, Codable {
    static let databaseTableName = "note_embedding"

    var id: Int64?
    var noteUUID: String
    var modelID: String
    var vectorJSON: String
    var updatedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

actor EmbeddingStore {
    static let shared = EmbeddingStore()

    private let dimensions = 64

    func upsertEmbedding(for note: Note, modelID: String = "hash-64") {
        let vector = embed(text: note.content)
        let vectorJSON = encode(vector: vector)

        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                if var existing = try EmbeddingRecord
                    .filter(Column("noteUUID") == note.uuid)
                    .fetchOne(db) {
                    existing.modelID = modelID
                    existing.vectorJSON = vectorJSON
                    existing.updatedAt = Date()
                    try existing.update(db)
                } else {
                    var record = EmbeddingRecord(
                        id: nil,
                        noteUUID: note.uuid,
                        modelID: modelID,
                        vectorJSON: vectorJSON,
                        updatedAt: Date()
                    )
                    try record.insert(db)
                }
            }
        } catch {
            print("[EmbeddingStore] upsert error: \(error)")
        }
    }

    func fetchAllEmbeddings() -> [(noteUUID: String, vector: [Double])] {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            return try dbQueue.read { db in
                let records = try EmbeddingRecord.fetchAll(db)
                return records.map { ($0.noteUUID, decode(vectorJSON: $0.vectorJSON)) }
            }
        } catch {
            print("[EmbeddingStore] fetch error: \(error)")
            return []
        }
    }

    private func embed(text: String) -> [Double] {
        var vector = Array(repeating: 0.0, count: dimensions)
        let tokens = text.lowercased().split { !$0.isLetter && !$0.isNumber }

        guard !tokens.isEmpty else { return vector }

        for token in tokens {
            let bucket = abs(token.hashValue) % dimensions
            vector[bucket] += 1
        }

        let norm = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    private func encode(vector: [Double]) -> String {
        guard let data = try? JSONEncoder().encode(vector),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private func decode(vectorJSON: String) -> [Double] {
        guard let data = vectorJSON.data(using: .utf8),
              let vector = try? JSONDecoder().decode([Double].self, from: data) else {
            return []
        }
        return vector
    }
}
