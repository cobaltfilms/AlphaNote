import Foundation
import GRDB

struct Note: Codable, Identifiable, Equatable {
    var id: Int64?
    var content: String
    var keyword: String
    var title: String
    var position: Int
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    static let knownKeywords: Set<String> = ["math", "list", "code", "timer"]

    init(
        id: Int64? = nil,
        content: String = "",
        keyword: String = "",
        title: String = "",
        position: Int = 0,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.keyword = keyword
        self.title = title
        self.position = position
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        detectKeyword()
    }

    mutating func detectKeyword() {
        let firstLine = content.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if Note.knownKeywords.contains(firstLine) {
            keyword = firstLine
            title = firstLine
        } else {
            keyword = ""
            title = firstLine
        }
    }
}

// MARK: - GRDB Conformances

extension Note: TableRecord, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "note"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    init(row: Row) {
        id = row["id"]
        content = row["content"]
        keyword = row["keyword"]
        title = row["title"]
        position = row["position"]
        isPinned = row["isPinned"]
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["content"] = content
        container["keyword"] = keyword
        container["title"] = title
        container["position"] = position
        container["isPinned"] = isPinned
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}

// MARK: - CRUD

extension Note {
    static func fetchAll() -> [Note] {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            return try dbQueue.read { db in
                try Note
                    .order(Column("isPinned").desc, Column("position").asc)
                    .fetchAll(db)
            }
        } catch {
            print("[Note] fetchAll error: \(error)")
            return []
        }
    }

    static func fetchByID(_ id: Int64) -> Note? {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            return try dbQueue.read { db in
                try Note.fetchOne(db, key: id)
            }
        } catch {
            print("[Note] fetchByID error: \(error)")
            return nil
        }
    }

    @discardableResult
    static func create(_ note: Note) -> Note {
        var newNote = note
        newNote.createdAt = Date()
        newNote.updatedAt = Date()
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                try newNote.insert(db)
            }
            return newNote
        } catch {
            print("[Note] create error: \(error)")
            return newNote
        }
    }

    static func update(_ note: Note) {
        var updated = note
        updated.updatedAt = Date()
        updated.detectKeyword()
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                try updated.update(db)
            }
        } catch {
            print("[Note] update error: \(error)")
        }
    }

    static func delete(_ note: Note) {
        guard note.id != nil else { return }
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                _ = try Note.deleteOne(db, key: note.id)
            }
        } catch {
            print("[Note] delete error: \(error)")
        }
    }

    static func deleteEmpty() {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                _ = try Note
                    .filter(Column("content") == "")
                    .deleteAll(db)
            }
        } catch {
            print("[Note] deleteEmpty error: \(error)")
        }
    }
}