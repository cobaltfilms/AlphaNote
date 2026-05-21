import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()
    static let databaseLocationUserDefaultsKey = "databaseLocation"
    static let defaultDatabaseFilename = "alph note.sqlite"

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
        databaseFileURL
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

        try migrator.migrate(dbQueue)
    }
}
