import Foundation

/// Synchro Nextcloud des pièces jointes (images et notes vocales), même logique
/// qu'Android (sync/AttachmentSync.kt).
///
/// Sur le serveur : `AlphaNote/attachments/<uuid de la note>/<nom>`, à côté de
/// `AlphaNote/notes/`. Les fichiers sont immuables (leur nom est un UUID) : un
/// fichier présent des deux côtés n'est jamais comparé ni renvoyé, il n'y a
/// donc pas de conflit. Rien n'est jamais supprimé en local parce qu'un fichier
/// manque sur le serveur.
enum AttachmentSyncPlanner {
    struct Item: Hashable {
        let noteUUID: String
        let name: String
    }

    struct Plan: Equatable {
        var uploads: [Item] = []
        var downloads: [Item] = []

        var isEmpty: Bool { uploads.isEmpty && downloads.isEmpty }
    }

    /// Entrée d'une liste WebDAV sous `attachments/` : un dossier de note
    /// (`name` nil) ou un fichier.
    struct RemoteEntry: Equatable {
        let noteUUID: String
        let name: String?
    }

    static let folderName = "attachments"
    private static let remoteMarker = "/AlphaNote/\(folderName)/"

    /// Nom de fichier sûr : les mêmes caractères que dans une référence
    /// `att:<nom>`, sans point initial — ni « . » ni « .. », pour ne jamais
    /// lire ni écrire hors du dossier de la note.
    static func isSafeName(_ name: String) -> Bool {
        guard !name.hasPrefix("."), name.count <= 200 else { return false }
        return name.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    /// UUID de note utilisable comme nom de dossier.
    static func isSafeNoteUUID(_ uuid: String) -> Bool {
        guard uuid.count <= 100 else { return false }
        return uuid.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    /// Pièces jointes à synchroniser : références `att:` des notes vivantes et
    /// non sécurisées, par UUID de note, sans doublon, dans l'ordre du texte.
    static func references(in notes: [Note]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for note in notes where !note.isDeleted && !note.isVault && isSafeNoteUUID(note.uuid) {
            var seen = Set<String>()
            let names = NoteAttachments.names(in: note.content).filter { isSafeName($0) && seen.insert($0).inserted }
            if !names.isEmpty { result[note.uuid] = names }
        }
        return result
    }

    /// Le plan : fichier local présent et absent du serveur → envoi ; fichier
    /// local absent et présent sur le serveur → téléchargement. Absent des deux
    /// côtés (l'appareil d'origine n'a pas encore synchronisé) : rien.
    static func plan(
        references: [String: [String]],
        local: [String: Set<String>],
        remote: [String: Set<String>]
    ) -> Plan {
        var plan = Plan()
        for uuid in references.keys.sorted() where isSafeNoteUUID(uuid) {
            var seen = Set<String>()
            for name in references[uuid] ?? [] where isSafeName(name) && seen.insert(name).inserted {
                let here = local[uuid]?.contains(name) ?? false
                let there = remote[uuid]?.contains(name) ?? false
                if here && !there { plan.uploads.append(Item(noteUUID: uuid, name: name)) }
                if !here && there { plan.downloads.append(Item(noteUUID: uuid, name: name)) }
            }
        }
        return plan
    }

    /// Lit un `href` de PROPFIND sous `…/AlphaNote/attachments/`. Nil pour le
    /// dossier lui-même, un chemin plus profond ou un nom qui n'est pas sûr.
    static func remoteEntry(fromHref href: String) -> RemoteEntry? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPath = URL(string: trimmed)?.path ?? (trimmed.removingPercentEncoding ?? trimmed)
        guard let marker = rawPath.range(of: remoteMarker) else { return nil }
        let isDirectory = trimmed.hasSuffix("/")
        let parts = rawPath[marker.upperBound...].split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        switch parts.count {
        case 1 where isDirectory && isSafeNoteUUID(parts[0]):
            return RemoteEntry(noteUUID: parts[0], name: nil)
        case 2 where !isDirectory && isSafeNoteUUID(parts[0]) && isSafeName(parts[1]):
            return RemoteEntry(noteUUID: parts[0], name: parts[1])
        default:
            return nil
        }
    }
}

/// Bilan d'une passe : ce qui a circulé, et ce qui a échoué.
struct AttachmentSyncOutcome: Equatable {
    var uploaded = 0
    var downloaded = 0
    var failed = 0
}

/// Exécution du plan contre Nextcloud. Une erreur ne remonte jamais : elle est
/// comptée et journalisée, la synchro des notes n'en dépend pas.
enum AttachmentSync {
    private static let listingsKey = "syncAttachmentListingsV1"

    /// Contenu connu d'un dossier distant, valable tant que son ETag ne change
    /// pas : en régime établi, une passe ne coûte qu'un PROPFIND.
    private struct Listing: Codable {
        let etag: String
        let names: [String]
    }

    static func run(client: NextcloudWebDAVClient, notes: [Note], scope: String) async -> AttachmentSyncOutcome {
        var outcome = AttachmentSyncOutcome()
        let references = AttachmentSyncPlanner.references(in: notes)
        guard !references.isEmpty else { return outcome }

        var local: [String: Set<String>] = [:]
        for (uuid, names) in references {
            local[uuid] = Set(names.filter { isPresent(NoteAttachments.fileURL(noteUUID: uuid, name: $0)) })
        }

        // Dossiers de notes présents sur le serveur (nil : `attachments` n'existe pas encore).
        let folders: [String: String?]
        var rootExists = true
        do {
            if let entries = try await client.listAttachmentFolders() {
                var found: [String: String?] = [:]
                for entry in entries {
                    guard let parsed = AttachmentSyncPlanner.remoteEntry(fromHref: entry.href), parsed.name == nil else { continue }
                    found[parsed.noteUUID] = .some(entry.etag)
                }
                folders = found
            } else {
                folders = [:]
                rootExists = false
            }
        } catch {
            log("liste des pièces jointes impossible : \(error.localizedDescription)")
            outcome.failed = 1
            return outcome
        }

        let known = storedListings(scope: scope)
        var listings: [String: Listing] = [:]
        var remote: [String: Set<String>] = [:]
        for uuid in references.keys.sorted() {
            guard let folder = folders[uuid] else { continue } // pas de dossier : rien sur le serveur
            if let etag = folder, let cached = known[uuid], cached.etag == etag {
                remote[uuid] = Set(cached.names)
                listings[uuid] = cached
                continue
            }
            do {
                let names = try await client.listAttachments(noteUUID: uuid).compactMap { entry -> String? in
                    guard let parsed = AttachmentSyncPlanner.remoteEntry(fromHref: entry.href), parsed.noteUUID == uuid else { return nil }
                    return parsed.name
                }
                remote[uuid] = Set(names)
                if let etag = folder { listings[uuid] = Listing(etag: etag, names: names.sorted()) }
            } catch {
                // Contenu inconnu : on ne touche pas à cette note pendant cette passe.
                log("liste du dossier \(uuid) impossible : \(error.localizedDescription)")
                outcome.failed += 1
                remote[uuid] = Set(references[uuid] ?? [])
                local[uuid] = Set(references[uuid] ?? [])
                if SyncEngine.isNetworkFailure(error) {
                    // Réseau coupé : on s'arrête là, la prochaine synchro reprendra.
                    storeListings(listings, scope: scope)
                    return outcome
                }
            }
        }
        storeListings(listings, scope: scope)

        let plan = AttachmentSyncPlanner.plan(references: references, local: local, remote: remote)
        var readyFolders = Set(folders.keys)

        for item in plan.downloads {
            do {
                let target = NoteAttachments.fileURL(noteUUID: item.noteUUID, name: item.name)
                if try await client.downloadAttachment(noteUUID: item.noteUUID, name: item.name, to: target) {
                    outcome.downloaded += 1
                } else {
                    outcome.failed += 1
                }
            } catch {
                log("téléchargement de \(item.noteUUID)/\(item.name) impossible : \(error.localizedDescription)")
                outcome.failed += 1
                if SyncEngine.isNetworkFailure(error) { return outcome }
            }
        }

        for item in plan.uploads {
            do {
                if !rootExists {
                    try await client.ensureAttachmentsFolder(noteUUID: nil)
                    rootExists = true
                }
                if !readyFolders.contains(item.noteUUID) {
                    try await client.ensureAttachmentsFolder(noteUUID: item.noteUUID)
                    readyFolders.insert(item.noteUUID)
                }
                let source = NoteAttachments.fileURL(noteUUID: item.noteUUID, name: item.name)
                try await client.uploadAttachment(noteUUID: item.noteUUID, name: item.name, from: source)
                outcome.uploaded += 1
            } catch {
                log("envoi de \(item.noteUUID)/\(item.name) impossible : \(error.localizedDescription)")
                outcome.failed += 1
                if SyncEngine.isNetworkFailure(error) { return outcome }
            }
        }
        return outcome
    }

    /// Un fichier vide (enregistrement raté) compte comme absent : il n'est pas envoyé.
    private static func isPresent(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return (size ?? 0) > 0
    }

    private static func log(_ message: String) {
        NSLog("AlphaNote — pièces jointes : %@", message)
    }

    private static func storedListings(scope: String) -> [String: Listing] {
        guard let data = UserDefaults.standard.data(forKey: listingsKey),
              let all = try? JSONDecoder().decode([String: [String: Listing]].self, from: data) else { return [:] }
        return all[scope] ?? [:]
    }

    private static func storeListings(_ listings: [String: Listing], scope: String) {
        var all = UserDefaults.standard.data(forKey: listingsKey)
            .flatMap { try? JSONDecoder().decode([String: [String: Listing]].self, from: $0) } ?? [:]
        all[scope] = listings
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: listingsKey)
        }
    }
}
