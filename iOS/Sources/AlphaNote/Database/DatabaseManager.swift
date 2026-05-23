import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()
    static let databaseLocationUserDefaultsKey = "databaseLocation"
    static let defaultDatabaseFilename = "alphanote.sqlite"

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
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("AlphaNote", isDirectory: true).path
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
        guard dbQueue == nil else { return }
        do {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
            try runMigrations()
        } catch {
            print("[AlphaNote iOS] DB setup failed: \(error)")
        }
    }

    var queue: DatabaseQueue? {
        if dbQueue == nil { setup() }
        return dbQueue
    }

    private func runMigrations() throws {
        guard let dbQueue else { return }
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "note") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("keyword", .text).notNull().defaults(to: "")
                t.column("title", .text).notNull().defaults(to: "")
                t.column("position", .integer).notNull().defaults(to: 0)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("isDeleted", .boolean).notNull().defaults(to: false)
                t.column("deletedAt", .datetime)
                t.column("lastSyncedAt", .datetime)
                t.column("lastModifiedByDeviceId", .text).notNull().defaults(to: "")
                t.column("aiSummary", .text).notNull().defaults(to: "")
                t.column("aiLastProcessedAt", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "app_state") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
