import Foundation
import SwiftUI

enum SyncRunTrigger {
    case startup
    case manual
    case scheduled
}

enum SyncStatus: Equatable {
    case idle
    case syncing
    case success(Date)
    case error(String)
}

@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    static let syncEnabledKey = "syncEnabled"
    static let syncIntervalMinutesKey = "syncIntervalMinutes"
    static let nextcloudServerURLKey = "nextcloudServerURL"
    static let nextcloudUsernameKey = "nextcloudUsername"

    @Published private(set) var status: SyncStatus = .idle

    private var timer: Timer?
    private var syncTask: Task<Void, Never>?

    private init() {
        UserDefaults.standard.register(defaults: [
            Self.syncEnabledKey: false,
            Self.syncIntervalMinutesKey: 5
        ])
    }

    func start() {
        configureTimer()
        if isSyncEnabled {
            runSync(trigger: .startup)
        }
    }

    func configureTimer() {
        timer?.invalidate()
        timer = nil

        guard isSyncEnabled else { return }

        let rawValue = UserDefaults.standard.integer(forKey: Self.syncIntervalMinutesKey)
        let intervalMinutes = rawValue > 0 ? rawValue : 5
        let interval = TimeInterval(intervalMinutes * 60)

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.runSync(trigger: .scheduled)
            }
        }
    }

    func notifyLocalChange() {
        // The scheduler picks this up on the next interval; manual sync remains available.
    }

    func runManualSync() {
        runSync(trigger: .manual)
    }

    func testConnection() async throws {
        let configuration = try currentConfiguration()
        let password = try currentPassword(configuration: configuration)
        let client = try NextcloudWebDAVClient(
            serverURL: configuration.serverURL,
            username: configuration.username,
            password: password
        )
        try await client.testConnection()
    }

    private func runSync(trigger: SyncRunTrigger) {
        guard syncTask == nil else { return }
        guard isSyncEnabled else { return }

        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.performSync(trigger: trigger)
            await MainActor.run {
                self.syncTask = nil
            }
        }
    }

    private func performSync(trigger: SyncRunTrigger) async {
        _ = trigger
        status = .syncing

        do {
            let configuration = try currentConfiguration()
            let password = try currentPassword(configuration: configuration)
            let client = try NextcloudWebDAVClient(
                serverURL: configuration.serverURL,
                username: configuration.username,
                password: password
            )

            try await client.ensureDirectories()
            _ = try await client.fetchManifest()

            let remoteEntries = try await client.listNotes()
            var remoteByUUID: [String: CloudNoteDTO] = [:]
            var remoteEtagsByUUID: [String: String] = [:]

            for entry in remoteEntries {
                guard let uuid = Self.uuidFromRemoteHref(entry.href) else { continue }
                if let payload = try await client.fetchNote(uuid: uuid) {
                    remoteByUUID[uuid] = payload.dto
                    remoteEtagsByUUID[uuid] = payload.etag
                }
            }

            let localNotes = Note.fetchAllIncludingDeleted()
            let localByUUID = Dictionary(uniqueKeysWithValues: localNotes.map { ($0.uuid, $0) })

            let merged = Self.merge(localByUUID: localByUUID, remoteByUUID: remoteByUUID)
            let syncTimestamp = Date()

            for (uuid, dto) in merged {
                let existing = localByUUID[uuid]
                let existingDTO = existing.map(CloudNoteDTO.init(note:))
                if existingDTO != dto {
                    let mergedNote = dto.toNote(existingID: existing?.id, lastSyncedAt: syncTimestamp)
                    Note.saveFromSync(mergedNote)
                }
            }

            let refreshedLocal = Note.fetchAllIncludingDeleted()
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: syncTimestamp) ?? syncTimestamp

            for note in refreshedLocal {
                let localDTO = CloudNoteDTO(note: note)
                let remoteDTO = remoteByUUID[note.uuid]

                if note.isDeleted, let deletedAt = note.deletedAt, deletedAt < cutoff {
                    try await client.deleteNote(uuid: note.uuid)
                    continue
                }

                let shouldUpload = Self.shouldUploadLocal(local: localDTO, remote: remoteDTO, lastSyncedAt: note.lastSyncedAt)
                if shouldUpload {
                    let remoteETag = remoteEtagsByUUID[note.uuid]
                    do {
                        try await client.uploadNote(localDTO, etag: remoteETag)
                    } catch {
                        // Retry once without ETag when remote state changed between pull and push.
                        try await client.uploadNote(localDTO, etag: nil)
                    }
                    Note.markLastSynced(forUUID: note.uuid, at: syncTimestamp)
                }
            }

            try await purgeExpiredTombstones(cutoff: cutoff, client: client)

            let finalNotes = Note.fetchAllIncludingDeleted()
            let manifest = ManifestDTO(
                deviceId: DeviceIdentity.currentDeviceID,
                exportedAt: syncTimestamp,
                noteUUIDs: finalNotes.map(\.uuid)
            )
            try await client.uploadManifest(manifest)

            status = .success(syncTimestamp)
            NotificationCenter.default.post(name: .alphaNoteDidSync, object: nil)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func purgeExpiredTombstones(cutoff: Date, client: NextcloudWebDAVClient) async throws {
        let deleted = Note.fetchAllIncludingDeleted().filter {
            $0.isDeleted && ($0.deletedAt ?? .distantFuture) < cutoff
        }

        for note in deleted {
            try await client.deleteNote(uuid: note.uuid)
        }

        Note.purgeDeleted(before: cutoff)
    }

    private var isSyncEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.syncEnabledKey) as? Bool ?? false
    }

    private func currentConfiguration() throws -> SyncConfiguration {
        let url = UserDefaults.standard.string(forKey: Self.nextcloudServerURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = UserDefaults.standard.string(forKey: Self.nextcloudUsernameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !url.isEmpty else { throw SyncConfigurationError.missingServerURL }
        guard !username.isEmpty else { throw SyncConfigurationError.missingUsername }

        return SyncConfiguration(serverURL: url, username: username)
    }

    private func currentPassword(configuration: SyncConfiguration) throws -> String {
        let password = try KeychainService.shared.readPassword(serverURL: configuration.serverURL, username: configuration.username)
        guard let password, !password.isEmpty else {
            throw SyncConfigurationError.missingPassword
        }
        return password
    }

    nonisolated static func merge(localByUUID: [String: Note], remoteByUUID: [String: CloudNoteDTO]) -> [String: CloudNoteDTO] {
        let localAsDTO = localByUUID.mapValues(CloudNoteDTO.init(note:))
        let allUUIDs = Set(localAsDTO.keys).union(remoteByUUID.keys)

        var merged: [String: CloudNoteDTO] = [:]
        for uuid in allUUIDs {
            let local = localAsDTO[uuid]
            let remote = remoteByUUID[uuid]

            switch (local, remote) {
            case let (lhs?, rhs?):
                merged[uuid] = resolveConflict(lhs, rhs)
            case let (lhs?, nil):
                merged[uuid] = lhs
            case let (nil, rhs?):
                merged[uuid] = rhs
            case (nil, nil):
                break
            }
        }

        return merged
    }

    nonisolated static func resolveConflict(_ lhs: CloudNoteDTO, _ rhs: CloudNoteDTO) -> CloudNoteDTO {
        if lhs.updatedAt > rhs.updatedAt { return lhs }
        if rhs.updatedAt > lhs.updatedAt { return rhs }

        if lhs.lastModifiedByDeviceId < rhs.lastModifiedByDeviceId {
            return lhs
        }
        if rhs.lastModifiedByDeviceId < lhs.lastModifiedByDeviceId {
            return rhs
        }

        if lhs.isDeleted != rhs.isDeleted {
            return lhs.isDeleted ? lhs : rhs
        }

        return lhs
    }

    nonisolated static func shouldUploadLocal(local: CloudNoteDTO, remote: CloudNoteDTO?, lastSyncedAt: Date?) -> Bool {
        guard let remote else {
            return true
        }

        if remote != local {
            let winner = resolveConflict(local, remote)
            if winner.uuid == local.uuid,
               winner.updatedAt == local.updatedAt,
               winner.lastModifiedByDeviceId == local.lastModifiedByDeviceId,
               winner.isDeleted == local.isDeleted {
                return true
            }
        }

        guard let lastSyncedAt else {
            return false
        }

        return local.updatedAt > lastSyncedAt
    }

    nonisolated static func uuidFromRemoteHref(_ href: String) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasSuffix("/") else { return nil }

        let filename: String
        if let url = URL(string: trimmed) {
            filename = url.lastPathComponent
        } else {
            filename = (trimmed as NSString).lastPathComponent
        }

        guard filename.hasSuffix(".json") else { return nil }
        let raw = String(filename.dropLast(5))
        return raw.removingPercentEncoding ?? raw
    }
}

private struct SyncConfiguration {
    let serverURL: String
    let username: String
}

enum SyncConfigurationError: LocalizedError {
    case missingServerURL
    case missingUsername
    case missingPassword

    var errorDescription: String? {
        switch self {
        case .missingServerURL:
            return "Nextcloud server URL is missing."
        case .missingUsername:
            return "Nextcloud username is missing."
        case .missingPassword:
            return "Nextcloud app password is missing."
        }
    }
}
