import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()
    static let databaseLocationUserDefaultsKey = "databaseLocation"
    static let defaultDatabaseFilename = "alphanote.sqlite"
    static let legacyDatabaseFilenames = [
        "alph note.sqlite",
        "AlphaNote.sqlite",
        "note.sqlite"
    ]

    private var dbQueue: DatabaseQueue?

    var databaseFileURL: URL {
        databaseDirectoryURL.appendingPathComponent(Self.defaultDatabaseFilename)
    }

    var databaseDirectoryURL: URL {
        let storedPath = UserDefaults.standard.string(forKey: Self.databaseLocationUserDefaultsKey)
        let resolvedPath = Self.resolveDatabaseDirectoryPath(storedPath)
        let directoryURL = URL(fileURLWithPath: resolvedPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    static func defaultDatabaseDirectoryPath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AlphaNote", isDirectory: true).path
    }

    static func resolveDatabaseDirectoryPath(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidate = trimmed.isEmpty ? defaultDatabaseDirectoryPath() : trimmed
        return (candidate as NSString).expandingTildeInPath
    }

    private var databaseURL: URL {
        resolvedDatabaseFileURL()
    }

    private init() {}

    func setup() {
        if dbQueue != nil {
            return
        }

        do {
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode=WAL")
                try db.execute(sql: "PRAGMA foreign_keys=ON")
            }
            dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: config)
            try migrate()
        } catch {
            print("[DatabaseManager] Setup failed: \(error)")
        }
    }

    func getDBQueue() -> DatabaseQueue {
        if dbQueue == nil {
            setup()
        }

        guard let db = dbQueue else {
            fatalError("Database initialization failed.")
        }
        return db
    }

    private func migrate() throws {
        guard let dbQueue else { return }

        var migrator = DatabaseMigrator()
        // Keep user data across app rebuilds/runs.
        // Automatic erase on schema change is convenient for prototyping,
        // but it makes notes appear to "reset" during development.
        migrator.eraseDatabaseOnSchemaChange = false

        migrator.registerMigration("v1") { db in
            try db.create(table: "note") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("content", .text).notNull().defaults(to: "")
                t.column("keyword", .text).notNull().defaults(to: "")
                t.column("title", .text).notNull().defaults(to: "")
                t.column("position", .integer).notNull().defaults(to: 0)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull().defaults(to: Date())
                t.column("updatedAt", .datetime).notNull().defaults(to: Date())
            }

            try db.create(table: "app_state") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v2_sync") { db in
            try db.alter(table: "note") { t in
                t.add(column: "uuid", .text)
                t.add(column: "archived", .boolean).notNull().defaults(to: false)
                t.add(column: "isDeleted", .boolean).notNull().defaults(to: false)
                t.add(column: "deletedAt", .datetime)
                t.add(column: "lastSyncedAt", .datetime)
                t.add(column: "lastModifiedByDeviceId", .text).notNull().defaults(to: "")
            }

            let rows = try Row.fetchAll(db, sql: "SELECT id FROM note WHERE uuid IS NULL OR trim(uuid) = ''")
            for row in rows {
                let id: Int64 = row["id"]
                try db.execute(
                    sql: "UPDATE note SET uuid = ? WHERE id = ?",
                    arguments: [UUID().uuidString.lowercased(), id]
                )
            }

            try db.execute(sql: "CREATE UNIQUE INDEX IF NOT EXISTS idx_note_uuid ON note(uuid)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_note_isDeleted ON note(isDeleted)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_note_updatedAt ON note(updatedAt)")
        }

        migrator.registerMigration("v3_ai") { db in
            try db.alter(table: "note") { t in
                t.add(column: "aiSummary", .text).notNull().defaults(to: "")
                t.add(column: "aiLastProcessedAt", .datetime)
            }

            try db.create(table: "note_embedding", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("noteUUID", .text).notNull()
                t.column("modelID", .text).notNull()
                t.column("vectorJSON", .text).notNull().defaults(to: "[]")
                t.column("updatedAt", .datetime).notNull().defaults(to: Date())
            }

            try db.execute(sql: "CREATE UNIQUE INDEX IF NOT EXISTS idx_note_embedding_uuid ON note_embedding(noteUUID)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_note_embedding_updatedAt ON note_embedding(updatedAt)")
        }

        try migrator.migrate(dbQueue)
    }

    private func resolvedDatabaseFileURL() -> URL {
        let canonicalURL = databaseDirectoryURL.appendingPathComponent(Self.defaultDatabaseFilename)
        migrateLegacyDatabaseFileIfNeeded(to: canonicalURL)
        return canonicalURL
    }

    private func migrateLegacyDatabaseFileIfNeeded(to canonicalURL: URL) {
        let fm = FileManager.default
        let directory = canonicalURL.deletingLastPathComponent()
        let legacyCandidates = Self.legacyDatabaseFilenames
            .map { directory.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }

        guard let sourceURL = latestModifiedFileURL(from: legacyCandidates) else {
            return
        }

        if fm.fileExists(atPath: canonicalURL.path) {
            let canonicalSize = fileSize(at: canonicalURL)
            let legacySize = fileSize(at: sourceURL)
            let shouldReplaceCanonical = canonicalSize < 131_072 &&
                legacySize > 262_144 &&
                legacySize > canonicalSize * 4
            guard shouldReplaceCanonical else { return }

            do {
                try fm.removeItem(at: canonicalURL)
            } catch {
                print("[DatabaseManager] Cannot replace small canonical DB: \(error.localizedDescription)")
                return
            }
        }

        do {
            try fm.moveItem(at: sourceURL, to: canonicalURL)
        } catch {
            do {
                try fm.copyItem(at: sourceURL, to: canonicalURL)
            } catch {
                print("[DatabaseManager] Legacy DB migration failed: \(error.localizedDescription)")
            }
        }
    }

    private func latestModifiedFileURL(from urls: [URL]) -> URL? {
        var latest: (url: URL, date: Date)?
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let date = values?.contentModificationDate ?? .distantPast
            if let current = latest {
                if date > current.date {
                    latest = (url, date)
                }
            } else {
                latest = (url, date)
            }
        }
        return latest?.url
    }

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
