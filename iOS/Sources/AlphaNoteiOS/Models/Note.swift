import Foundation
import GRDB

struct Note: Codable, Identifiable, Equatable {
    var id: Int64?
    var uuid: String
    var content: String
    var keyword: String
    var title: String
    var position: Int
    var isPinned: Bool
    var archived: Bool
    var isDeleted: Bool
    var deletedAt: Date?
    var lastSyncedAt: Date?
    var lastModifiedByDeviceId: String
    var aiSummary: String
    var aiLastProcessedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    static let knownKeywords: Set<String> = ["math", "list", "code", "timer"]

    init(
        id: Int64? = nil,
        uuid: String = UUID().uuidString.lowercased(),
        content: String = "",
        keyword: String = "",
        title: String = "",
        position: Int = 0,
        isPinned: Bool = false,
        archived: Bool = false,
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        lastSyncedAt: Date? = nil,
        lastModifiedByDeviceId: String = DeviceIdentity.currentDeviceID,
        aiSummary: String = "",
        aiLastProcessedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.uuid = uuid
        self.content = content
        self.keyword = keyword
        self.title = title
        self.position = position
        self.isPinned = isPinned
        self.archived = archived
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.lastSyncedAt = lastSyncedAt
        self.lastModifiedByDeviceId = lastModifiedByDeviceId
        self.aiSummary = aiSummary
        self.aiLastProcessedAt = aiLastProcessedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        detectKeyword()
    }

    mutating func detectKeyword() {
        let rawFirstLine = content.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        let firstLine = rawFirstLine.lowercased()

        if Note.knownKeywords.contains(firstLine) {
            keyword = firstLine
            return
        }

        if let colonIndex = rawFirstLine.firstIndex(of: ":") {
            let possibleKeyword = String(rawFirstLine[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
            if Note.knownKeywords.contains(possibleKeyword) {
                keyword = possibleKeyword
                return
            }
        }

        keyword = ""
    }

    var effectiveTitle: String {
        let explicitTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitTitle.isEmpty {
            return explicitTitle
        }

        let lines = content.components(separatedBy: .newlines)
        guard let firstNonEmptyRaw = lines.first(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return ""
        }

        if let colonIndex = firstNonEmptyRaw.firstIndex(of: ":") {
            let possibleKeyword = String(firstNonEmptyRaw[..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if Note.knownKeywords.contains(possibleKeyword) {
                let customTitle = String(firstNonEmptyRaw[firstNonEmptyRaw.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return customTitle.isEmpty ? possibleKeyword : customTitle
            }
        }

        return firstNonEmptyRaw
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
        uuid = row["uuid"] ?? UUID().uuidString.lowercased()
        content = row["content"]
        keyword = row["keyword"]
        title = row["title"]
        position = row["position"]
        isPinned = row["isPinned"]
        archived = row["archived"] ?? false
        isDeleted = row["isDeleted"] ?? false
        deletedAt = row["deletedAt"]
        lastSyncedAt = row["lastSyncedAt"]
        lastModifiedByDeviceId = row["lastModifiedByDeviceId"] ?? ""
        aiSummary = row["aiSummary"] ?? ""
        aiLastProcessedAt = row["aiLastProcessedAt"]
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["uuid"] = uuid
        container["content"] = content
        container["keyword"] = keyword
        container["title"] = title
        container["position"] = position
        container["isPinned"] = isPinned
        container["archived"] = archived
        container["isDeleted"] = isDeleted
        container["deletedAt"] = deletedAt
        container["lastSyncedAt"] = lastSyncedAt
        container["lastModifiedByDeviceId"] = lastModifiedByDeviceId
        container["aiSummary"] = aiSummary
        container["aiLastProcessedAt"] = aiLastProcessedAt
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}

// MARK: - CRUD

extension Note {
    static func fetchAll() -> [Note] {
        fetchAll(includeDeleted: false)
    }

    static func fetchAllIncludingDeleted() -> [Note] {
        fetchAll(includeDeleted: true)
    }

    private static func fetchAll(includeDeleted: Bool) -> [Note] {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            return try dbQueue.read { db in
                var request = Note
                    .order(Column("isPinned").desc, Column("position").asc)
                if !includeDeleted {
                    request = request.filter(Column("isDeleted") == false)
                }
                return try request.fetchAll(db)
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

    static func fetchByUUID(_ uuid: String) -> Note? {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            return try dbQueue.read { db in
                try Note.filter(Column("uuid") == uuid).fetchOne(db)
            }
        } catch {
            print("[Note] fetchByUUID error: \(error)")
            return nil
        }
    }

    @discardableResult
    static func create(_ note: Note) -> Note {
        var newNote = note
        if newNote.uuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newNote.uuid = UUID().uuidString.lowercased()
        }
        newNote.createdAt = Date()
        newNote.updatedAt = Date()
        newNote.lastModifiedByDeviceId = DeviceIdentity.currentDeviceID
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
        updated.lastModifiedByDeviceId = DeviceIdentity.currentDeviceID
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
        softDelete(note)
    }

    static func softDelete(_ note: Note) {
        guard let id = note.id else { return }
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: """
                    UPDATE note
                    SET isDeleted = 1,
                        deletedAt = ?,
                        updatedAt = ?,
                        lastModifiedByDeviceId = ?
                    WHERE id = ?
                    """,
                    arguments: [Date(), Date(), DeviceIdentity.currentDeviceID, id]
                )
            }
        } catch {
            print("[Note] delete error: \(error)")
        }
    }

    static func deleteEmpty() {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: """
                    UPDATE note
                    SET isDeleted = 1,
                        deletedAt = ?,
                        updatedAt = ?,
                        lastModifiedByDeviceId = ?
                    WHERE trim(content) = '' AND isDeleted = 0
                    """,
                    arguments: [Date(), Date(), DeviceIdentity.currentDeviceID]
                )
            }
        } catch {
            print("[Note] deleteEmpty error: \(error)")
        }
    }

    static func saveFromSync(_ note: Note) {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                if var existing = try Note.filter(Column("uuid") == note.uuid).fetchOne(db) {
                    existing.content = note.content
                    existing.keyword = note.keyword
                    existing.title = note.title
                    existing.position = note.position
                    existing.isPinned = note.isPinned
                    existing.archived = note.archived
                    existing.isDeleted = note.isDeleted
                    existing.deletedAt = note.deletedAt
                    existing.lastSyncedAt = note.lastSyncedAt
                    existing.lastModifiedByDeviceId = note.lastModifiedByDeviceId
                    if !note.aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        existing.aiSummary = note.aiSummary
                    }
                    if note.aiLastProcessedAt != nil {
                        existing.aiLastProcessedAt = note.aiLastProcessedAt
                    }
                    existing.createdAt = note.createdAt
                    existing.updatedAt = note.updatedAt
                    try existing.update(db)
                } else {
                    var inserted = note
                    inserted.id = nil
                    try inserted.insert(db)
                }
            }
        } catch {
            print("[Note] saveFromSync error: \(error)")
        }
    }

    static func markLastSynced(forUUID uuid: String, at date: Date) {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE note SET lastSyncedAt = ? WHERE uuid = ?",
                    arguments: [date, uuid]
                )
            }
        } catch {
            print("[Note] markLastSynced error: \(error)")
        }
    }

    static func purgeDeleted(before cutoff: Date) {
        let dbQueue = DatabaseManager.shared.getDBQueue()
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "DELETE FROM note WHERE isDeleted = 1 AND deletedAt IS NOT NULL AND deletedAt < ?",
                    arguments: [cutoff]
                )
            }
        } catch {
            print("[Note] purgeDeleted error: \(error)")
        }
    }
}
