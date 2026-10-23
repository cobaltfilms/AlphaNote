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

    /// Message affiché dans Réglages › Avancé si l'emplacement configuré n'a pas
    /// pu être ouvert (AlphaNote retombe alors sur le dossier par défaut).
    private(set) var setupErrorMessage: String?

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

    private init() {}

    // MARK: - Ouverture

    func setup() {
        if dbQueue != nil { return }

        let preferredURL = resolvedDatabaseFileURL()
        if let queue = openQueue(at: preferredURL) {
            dbQueue = queue
            return
        }

        // Repli : dossier par défaut, sans toucher à la base existante.
        let defaultDirectory = URL(fileURLWithPath: Self.defaultDatabaseDirectoryPath(), isDirectory: true)
        try? FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
        let fallbackURL = defaultDirectory.appendingPathComponent(Self.defaultDatabaseFilename)
        if fallbackURL.standardizedFileURL != preferredURL.standardizedFileURL, let queue = openQueue(at: fallbackURL) {
            setupErrorMessage = "Impossible d'ouvrir la base dans « \(preferredURL.deletingLastPathComponent().path) ». AlphaNote utilise le dossier par défaut."
            UserDefaults.standard.removeObject(forKey: Self.databaseLocationUserDefaultsKey)
            dbQueue = queue
            return
        }

        // Dernier recours : base en mémoire, pour que l'app démarre quand même.
        setupErrorMessage = "Impossible d'ouvrir la base de données : les notes de cette session ne seront pas conservées."
        if let queue = try? DatabaseQueue() {
            dbQueue = queue
            try? migrate(queue)
        }
    }

    private func openQueue(at url: URL) -> DatabaseQueue? {
        do {
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode=WAL")
                try db.execute(sql: "PRAGMA foreign_keys=ON")
            }
            let queue = try DatabaseQueue(path: url.path, configuration: config)
            try migrate(queue)
            return queue
        } catch {
            print("[DatabaseManager] Ouverture impossible (\(url.path)) : \(error)")
            return nil
        }
    }

    func getDBQueue() -> DatabaseQueue {
        if dbQueue == nil { setup() }
        guard let db = dbQueue else {
            fatalError("Database initialization failed.")
        }
        return db
    }

    /// Copie la base (après checkpoint WAL) dans `directory` et mémorise ce
    /// dossier. L'app doit être relancée ensuite ; l'ancien fichier est conservé.
    func relocateDatabase(to directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(Self.defaultDatabaseFilename)
        let source = databaseFileURL
        guard destination.standardizedFileURL != source.standardizedFileURL else { return }

        if let dbQueue {
            _ = try dbQueue.writeWithoutTransaction { db in
                try db.checkpoint(.truncate)
            }
        }
        if fm.fileExists(atPath: destination.path) {
            let backup = directory.appendingPathComponent("alphanote-\(Int(Date().timeIntervalSince1970)).sqlite.bak")
            try fm.moveItem(at: destination, to: backup)
        }
        try fm.copyItem(at: source, to: destination)
        UserDefaults.standard.set(directory.path, forKey: Self.databaseLocationUserDefaultsKey)
    }

    // MARK: - Migrations

    private func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
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
                try db.execute(sql: "UPDATE note SET uuid = ? WHERE id = ?", arguments: [UUID().uuidString.lowercased(), id])
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

    // MARK: - Anciens noms de fichier

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

        guard let sourceURL = latestModifiedFileURL(from: legacyCandidates) else { return }

        if fm.fileExists(atPath: canonicalURL.path) {
            let canonicalSize = fileSize(at: canonicalURL)
            let legacySize = fileSize(at: sourceURL)
            let shouldReplaceCanonical = canonicalSize < 131_072 && legacySize > 262_144 && legacySize > canonicalSize * 4
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
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if latest == nil || date > latest!.date {
                latest = (url, date)
            }
        }
        return latest?.url
    }

    private func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }
}
