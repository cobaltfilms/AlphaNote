import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?

    private var databaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AlphaNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("alph note.sqlite")
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

        try migrator.migrate(dbQueue)
    }
}
