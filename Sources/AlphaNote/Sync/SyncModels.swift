import Foundation

struct CloudNoteDTO: Codable, Equatable {
    let schemaVersion: Int
    let uuid: String
    let content: String
    let keyword: String
    let title: String
    let position: Int
    let isPinned: Bool
    let archived: Bool
    let isDeleted: Bool
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let lastModifiedByDeviceId: String

    init(note: Note) {
        self.schemaVersion = 1
        self.uuid = note.uuid
        self.content = note.content
        self.keyword = note.keyword
        self.title = note.title
        self.position = note.position
        self.isPinned = note.isPinned
        self.archived = note.archived
        self.isDeleted = note.isDeleted
        self.deletedAt = note.deletedAt
        self.createdAt = note.createdAt
        self.updatedAt = note.updatedAt
        self.lastModifiedByDeviceId = note.lastModifiedByDeviceId
    }

    func toNote(existingID: Int64?, lastSyncedAt: Date?) -> Note {
        Note(
            id: existingID,
            uuid: uuid,
            content: content,
            keyword: keyword,
            title: title,
            position: position,
            isPinned: isPinned,
            archived: archived,
            isDeleted: isDeleted,
            deletedAt: deletedAt,
            lastSyncedAt: lastSyncedAt,
            lastModifiedByDeviceId: lastModifiedByDeviceId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct ManifestDTO: Codable, Equatable {
    let schemaVersion: Int
    let deviceId: String
    let exportedAt: Date
    let noteUUIDs: [String]

    init(deviceId: String, exportedAt: Date, noteUUIDs: [String]) {
        self.schemaVersion = 1
        self.deviceId = deviceId
        self.exportedAt = exportedAt
        self.noteUUIDs = noteUUIDs.sorted()
    }
}

enum CloudJSONCoder {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .formatted(formatter)
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(formatter)
        return decoder
    }
}
