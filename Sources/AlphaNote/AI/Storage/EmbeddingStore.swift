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

    /// Réindexe la note si son embedding manque, vient d'un ancien modèle, ou
    /// est antérieur à sa dernière modification.
    func upsertEmbedding(for note: Note, force: Bool = false) {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                let existing = try EmbeddingRecord.filter(Column("noteUUID") == note.uuid).fetchOne(db)
                if !force, let existing,
                   existing.modelID == HashEmbedding.modelID,
                   existing.updatedAt >= note.updatedAt {
                    return
                }

                let vectorJSON = Self.encode(HashEmbedding.embed(text: note.effectiveTitle + "\n" + note.content))
                if var existing {
                    existing.modelID = HashEmbedding.modelID
                    existing.vectorJSON = vectorJSON
                    existing.updatedAt = Date()
                    try existing.update(db)
                } else {
                    var record = EmbeddingRecord(
                        id: nil, noteUUID: note.uuid, modelID: HashEmbedding.modelID,
                        vectorJSON: vectorJSON, updatedAt: Date()
                    )
                    try record.insert(db)
                }
            }
        } catch {
            print("[EmbeddingStore] upsert error: \(error)")
        }
    }

    func removeEmbedding(noteUUID: String) {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        try? dbQueue.write { db in
            _ = try EmbeddingRecord.filter(Column("noteUUID") == noteUUID).deleteAll(db)
        }
    }

    func fetchAllEmbeddings() -> [(noteUUID: String, vector: [Double])] {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            return try dbQueue.read { db in
                try EmbeddingRecord
                    .filter(Column("modelID") == HashEmbedding.modelID)
                    .fetchAll(db)
                    .map { ($0.noteUUID, Self.decode($0.vectorJSON)) }
            }
        } catch {
            print("[EmbeddingStore] fetch error: \(error)")
            return []
        }
    }

    private static func encode(_ vector: [Double]) -> String {
        guard let data = try? JSONEncoder().encode(vector),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static func decode(_ vectorJSON: String) -> [Double] {
        guard let data = vectorJSON.data(using: .utf8),
              let vector = try? JSONDecoder().decode([Double].self, from: data) else { return [] }
        return vector
    }
}
