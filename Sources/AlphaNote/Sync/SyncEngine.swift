import Foundation
import SwiftUI

extension Notification.Name {
    /// Une synchro a modifié la base : les listes de notes se rechargent.
    static let alphaNoteDidSync = Notification.Name("alphaNoteDidSync")
}

enum SyncRunTrigger {
    case startup
    case manual
    case scheduled
    case localChange
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
    private static let remoteETagsKey = "syncRemoteETagsV1"

    @Published private(set) var status: SyncStatus = .idle

    private var timer: Timer?
    private var syncTask: Task<Void, Never>?
    private var localChangeTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var rerunRequested = false
    /// Délai entre une modification locale et la sync qui la pousse.
    private let localChangeDelay: UInt64 = 30_000_000_000

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
        let interval = TimeInterval((rawValue > 0 ? rawValue : 5) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runSync(trigger: .scheduled) }
        }
    }

    /// Une modification locale programme une sync différée (regroupe les
    /// frappes successives), sans attendre le prochain intervalle.
    func notifyLocalChange() {
        guard isSyncEnabled else { return }
        localChangeTask?.cancel()
        localChangeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.localChangeDelay ?? 30_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.runSync(trigger: .localChange) }
        }
    }

    func runManualSync() {
        runSync(trigger: .manual)
    }

    func testConnection() async throws {
        let configuration = try currentConfiguration()
        let password = try currentPassword(configuration: configuration)
        let client = try NextcloudWebDAVClient(serverURL: configuration.serverURL, username: configuration.username, password: password)
        try await client.testConnection()
    }

    private func runSync(trigger: SyncRunTrigger) {
        guard isSyncEnabled else { return }
        guard syncTask == nil else {
            rerunRequested = true
            return
        }

        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.performSync(trigger: trigger)
            await MainActor.run {
                self.syncTask = nil
                if self.rerunRequested {
                    self.rerunRequested = false
                    self.runSync(trigger: .localChange)
                }
            }
        }
    }

    private func performSync(trigger: SyncRunTrigger) async {
        status = .syncing

        do {
            let configuration = try currentConfiguration()
            let password = try currentPassword(configuration: configuration)
            let client = try NextcloudWebDAVClient(serverURL: configuration.serverURL, username: configuration.username, password: password)
            let etagScope = "\(configuration.username)@\(configuration.serverURL)"
            var knownETags = storedETags(scope: etagScope)

            try await client.ensureDirectories()
            _ = try await client.fetchManifest()

            let localNotes = Note.fetchAllIncludingDeleted()
            let localByUUID = Dictionary(localNotes.map { ($0.uuid, $0) }, uniquingKeysWith: { _, last in last })

            // Téléchargement des notes distantes — uniquement celles dont l'ETag
            // a changé depuis la dernière sync (les autres sont identiques à
            // notre copie synchronisée).
            let remoteEntries = try await client.listNotes()
            var remoteByUUID: [String: CloudNoteDTO] = [:]
            var remoteEtagsByUUID: [String: String] = [:]
            var seenRemoteUUIDs = Set<String>()

            for entry in remoteEntries {
                guard let uuid = Self.uuidFromRemoteHref(entry.href) else { continue }
                seenRemoteUUIDs.insert(uuid)

                if let etag = entry.etag, knownETags[uuid] == etag,
                   let local = localByUUID[uuid], local.lastSyncedAt != nil {
                    remoteByUUID[uuid] = Self.syncedBaseline(for: local)
                    remoteEtagsByUUID[uuid] = etag
                    continue
                }

                if let payload = try await client.fetchNote(uuid: uuid) {
                    remoteByUUID[uuid] = payload.dto
                    if let etag = payload.etag ?? entry.etag {
                        remoteEtagsByUUID[uuid] = etag
                    }
                }
            }

            let merged = Self.merge(localByUUID: localByUUID, remoteByUUID: remoteByUUID)
            let syncTimestamp = Date()

            for (uuid, dto) in merged {
                let existing = localByUUID[uuid]
                let existingDTO = existing.map(CloudNoteDTO.init(note:))
                if existingDTO != dto {
                    Note.saveFromSync(dto.toNote(existingID: existing?.id, lastSyncedAt: syncTimestamp))
                }
            }

            let refreshedLocal = Note.fetchAllIncludingDeleted()
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: syncTimestamp) ?? syncTimestamp

            for note in refreshedLocal {
                let localDTO = CloudNoteDTO(note: note)
                let remoteDTO = remoteByUUID[note.uuid]

                if note.isDeleted, let deletedAt = note.deletedAt, deletedAt < cutoff {
                    try await client.deleteNote(uuid: note.uuid)
                    knownETags[note.uuid] = nil
                    continue
                }

                guard Self.shouldUploadLocal(local: localDTO, remote: remoteDTO, lastSyncedAt: note.lastSyncedAt) else {
                    if let etag = remoteEtagsByUUID[note.uuid] { knownETags[note.uuid] = etag }
                    continue
                }

                let remoteETag = remoteEtagsByUUID[note.uuid]
                var newETag: String?
                do {
                    newETag = try await client.uploadNote(localDTO, etag: remoteETag)
                } catch {
                    // Le distant a bougé entre lecture et écriture : on réessaie sans condition.
                    newETag = try await client.uploadNote(localDTO, etag: nil)
                }
                Note.markLastSynced(forUUID: note.uuid, at: syncTimestamp)
                knownETags[note.uuid] = newETag // nil → re-téléchargée la prochaine fois
            }

            try await purgeExpiredTombstones(cutoff: cutoff, client: client)

            for uuid in knownETags.keys where !seenRemoteUUIDs.contains(uuid) && localByUUID[uuid]?.lastSyncedAt == nil {
                knownETags[uuid] = nil
            }
            storeETags(knownETags, scope: etagScope)

            let finalNotes = Note.fetchAllIncludingDeleted()
            try await client.uploadManifest(ManifestDTO(
                deviceId: DeviceIdentity.currentDeviceID,
                exportedAt: syncTimestamp,
                noteUUIDs: finalNotes.map(\.uuid)
            ))

            status = .success(syncTimestamp)
            NotificationCenter.default.post(name: .alphaNoteDidSync, object: nil)
        } catch {
            status = .error(Self.describe(error))
            if Self.isNetworkFailure(error) { scheduleRetry() }
        }
    }

    /// Coupure ou lenteur réseau : nouvel essai dans une minute, sans attendre
    /// l'intervalle (5 min par défaut).
    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.runSync(trigger: .scheduled) }
        }
    }

    nonisolated static func isNetworkFailure(_ error: Error) -> Bool {
        (error as NSError).domain == NSURLErrorDomain
    }

    nonisolated static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return error.localizedDescription }
        switch nsError.code {
        case NSURLErrorTimedOut:
            return "Le serveur Nextcloud a mis trop de temps à répondre. Nouvel essai dans une minute."
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return "Pas de connexion réseau. Nouvel essai dans une minute."
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorCannotConnectToHost:
            return "Serveur Nextcloud injoignable. Nouvel essai dans une minute."
        default:
            return "Erreur réseau (\(nsError.localizedDescription)). Nouvel essai dans une minute."
        }
    }

    /// Image distante d'une note inchangée côté serveur : ce qu'on y a écrit à
    /// la dernière sync, c'est-à-dire la note locale sans ses modifications
    /// postérieures à `lastSyncedAt`. Comme on ne garde pas ce snapshot, on
    /// utilise la note locale : si elle a changé depuis, `shouldUploadLocal`
    /// la pousse (updatedAt > lastSyncedAt) ; sinon rien ne bouge.
    nonisolated private static func syncedBaseline(for local: Note) -> CloudNoteDTO {
        CloudNoteDTO(note: local)
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
        guard let password, !password.isEmpty else { throw SyncConfigurationError.missingPassword }
        return password
    }

    // MARK: ETags

    private func storedETags(scope: String) -> [String: String] {
        let all = UserDefaults.standard.dictionary(forKey: Self.remoteETagsKey) as? [String: [String: String]] ?? [:]
        return all[scope] ?? [:]
    }

    private func storeETags(_ etags: [String: String], scope: String) {
        var all = UserDefaults.standard.dictionary(forKey: Self.remoteETagsKey) as? [String: [String: String]] ?? [:]
        all[scope] = etags
        UserDefaults.standard.set(all, forKey: Self.remoteETagsKey)
    }

    // MARK: Fusion (pure, testée)

    nonisolated static func merge(localByUUID: [String: Note], remoteByUUID: [String: CloudNoteDTO]) -> [String: CloudNoteDTO] {
        let localAsDTO = localByUUID.mapValues(CloudNoteDTO.init(note:))
        var merged: [String: CloudNoteDTO] = [:]
        for uuid in Set(localAsDTO.keys).union(remoteByUUID.keys) {
            switch (localAsDTO[uuid], remoteByUUID[uuid]) {
            case let (lhs?, rhs?): merged[uuid] = resolveConflict(lhs, rhs)
            case let (lhs?, nil): merged[uuid] = lhs
            case let (nil, rhs?): merged[uuid] = rhs
            case (nil, nil): break
            }
        }
        return merged
    }

    nonisolated static func resolveConflict(_ lhs: CloudNoteDTO, _ rhs: CloudNoteDTO) -> CloudNoteDTO {
        if lhs.updatedAt > rhs.updatedAt { return lhs }
        if rhs.updatedAt > lhs.updatedAt { return rhs }
        if lhs.lastModifiedByDeviceId < rhs.lastModifiedByDeviceId { return lhs }
        if rhs.lastModifiedByDeviceId < lhs.lastModifiedByDeviceId { return rhs }
        if lhs.isDeleted != rhs.isDeleted { return lhs.isDeleted ? lhs : rhs }
        return lhs
    }

    nonisolated static func shouldUploadLocal(local: CloudNoteDTO, remote: CloudNoteDTO?, lastSyncedAt: Date?) -> Bool {
        guard let remote else { return true }

        if remote != local {
            let winner = resolveConflict(local, remote)
            if winner.uuid == local.uuid,
               winner.updatedAt == local.updatedAt,
               winner.lastModifiedByDeviceId == local.lastModifiedByDeviceId,
               winner.isDeleted == local.isDeleted {
                return true
            }
        }

        guard let lastSyncedAt else { return false }
        return local.updatedAt > lastSyncedAt
    }

    nonisolated static func uuidFromRemoteHref(_ href: String) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasSuffix("/") else { return nil }
        let filename = URL(string: trimmed)?.lastPathComponent ?? (trimmed as NSString).lastPathComponent
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
        case .missingServerURL: return "L'adresse du serveur Nextcloud manque."
        case .missingUsername: return "L'identifiant Nextcloud manque."
        case .missingPassword: return "Le mot de passe d'application Nextcloud manque."
        }
    }
}
