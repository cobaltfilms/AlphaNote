import CryptoKit
import Foundation
import Network

// Synchro directe sur le réseau local (0.3.0).
//
// Le Mac sert HTTP sur le LAN, annoncé en Bonjour `_alphanote._tcp`. Un téléphone
// s'appaire une fois avec un code à 6 chiffres affiché ici, puis reçoit un jeton
// (`Authorization: Bearer`) qui authentifie chaque requête. Le téléphone tire la
// liste des notes et pousse les siennes ; la fusion est celle de la synchro Nextcloud
// (`SyncEngine.resolveConflict`). Voir docs/SYNC-LAN.md pour le protocole.

// MARK: - HTTP minimal

struct LANRequest: Equatable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    var bearerToken: String? {
        guard let value = headers["authorization"], value.lowercased().hasPrefix("bearer ") else { return nil }
        return String(value.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
    }
}

struct LANResponse: Equatable {
    let status: Int
    let body: Data

    static func json(_ status: Int, _ object: Any) -> LANResponse {
        LANResponse(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }

    static func empty(_ status: Int) -> LANResponse {
        LANResponse(status: status, body: Data())
    }
}

enum LANHTTP {
    static let maxRequestBytes = 5 * 1024 * 1024

    enum ParseResult: Equatable {
        case incomplete
        case complete(LANRequest)
        case invalid
    }

    /// Lit une requête HTTP/1.1 complète (en-têtes + Content-Length) dans `buffer`.
    static func parse(_ buffer: Data) -> ParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else {
            return buffer.count > maxRequestBytes ? .invalid : .incomplete
        }
        guard let head = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxRequestBytes else { return .invalid }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }
        let body = buffer[bodyStart..<(bodyStart + length)]
        return .complete(LANRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: Data(body)))
    }

    static func serialize(_ response: LANResponse) -> Data {
        let reason: String
        switch response.status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        let head = "HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + response.body
    }
}

// MARK: - Appairage

/// Un téléphone appairé : seul le haché de son jeton est conservé.
struct LANPairedDevice: Codable, Equatable {
    let deviceId: String
    let name: String
    let tokenHash: String
    let pairedAt: Date
}

/// Code d'appairage à usage unique, valable 5 minutes, bloqué après 5 essais.
final class LANPairing {
    static let codeLifetime: TimeInterval = 5 * 60
    static let maxAttempts = 5
    static let pairedDevicesKey = "lanPairedDevices"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var code: String?
    private var expiresAt = Date.distantPast
    private var attempts = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Nouveau code à 6 chiffres (remplace le précédent).
    func beginPairing(now: Date = Date()) -> String {
        lock.lock(); defer { lock.unlock() }
        let newCode = String(format: "%06d", Int.random(in: 0...999_999))
        code = newCode
        expiresAt = now.addingTimeInterval(Self.codeLifetime)
        attempts = 0
        return newCode
    }

    var activeCode: String? {
        lock.lock(); defer { lock.unlock() }
        return code
    }

    var pairedDevices: [LANPairedDevice] {
        guard let data = defaults.data(forKey: Self.pairedDevicesKey),
              let list = try? JSONDecoder().decode([LANPairedDevice].self, from: data) else { return [] }
        return list
    }

    /// Vérifie le code et, s'il est bon, enregistre le téléphone et retourne son jeton.
    func complete(code given: String, deviceId: String, name: String, now: Date = Date()) -> String? {
        lock.lock()
        guard let expected = code, now < expiresAt, attempts < Self.maxAttempts else {
            lock.unlock()
            return nil
        }
        guard given == expected else {
            attempts += 1
            if attempts >= Self.maxAttempts { code = nil }
            lock.unlock()
            return nil
        }
        code = nil
        lock.unlock()

        let token = Self.randomToken()
        var devices = pairedDevices.filter { $0.deviceId != deviceId }
        devices.append(LANPairedDevice(deviceId: deviceId, name: name, tokenHash: Self.hash(token), pairedAt: now))
        if let data = try? JSONEncoder().encode(devices) { defaults.set(data, forKey: Self.pairedDevicesKey) }
        return token
    }

    /// Un jeton est valide s'il correspond à un téléphone appairé.
    func isAuthorized(token: String?) -> Bool {
        guard let token else { return false }
        let hashed = Self.hash(token)
        return pairedDevices.contains { $0.tokenHash == hashed }
    }

    func unpair(deviceId: String) {
        let remaining = pairedDevices.filter { $0.deviceId != deviceId }
        if let data = try? JSONEncoder().encode(remaining) { defaults.set(data, forKey: Self.pairedDevicesKey) }
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Routage

/// Accès aux notes, abstrait pour les tests (la vraie implémentation passe par GRDB).
protocol LANNoteStore {
    func allNotes() -> [CloudNoteDTO]
    /// Fusionne une note reçue et retourne la version qui fait autorité.
    func merge(incoming: CloudNoteDTO, now: Date) -> CloudNoteDTO
}

struct LANDatabaseNoteStore: LANNoteStore {
    func allNotes() -> [CloudNoteDTO] {
        Note.fetchAllIncludingDeleted().map(CloudNoteDTO.init(note:))
    }

    func merge(incoming: CloudNoteDTO, now: Date) -> CloudNoteDTO {
        let existing = Note.fetchAllIncludingDeleted().first { $0.uuid == incoming.uuid }
        guard let existing else {
            Note.saveFromSync(incoming.toNote(existingID: nil, lastSyncedAt: now))
            return incoming
        }
        let localDTO = CloudNoteDTO(note: existing)
        let winner = SyncEngine.resolveConflict(localDTO, incoming)
        if winner != localDTO {
            Note.saveFromSync(winner.toNote(existingID: existing.id, lastSyncedAt: now))
        }
        return winner
    }
}

/// Table de routage du serveur. Pure : pas de réseau ici.
struct LANSyncRouter {
    let pairing: LANPairing
    let store: LANNoteStore
    let serverName: String
    var now: () -> Date = { Date() }

    func handle(_ request: LANRequest) -> LANResponse {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path

        switch (request.method, path) {
        case ("GET", "/v1/info"):
            return .json(200, ["name": serverName, "schemaVersion": 1])

        case ("POST", "/v1/pair"):
            guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let code = object["code"] as? String,
                  let deviceId = object["deviceId"] as? String, !deviceId.isEmpty else {
                return .json(400, ["error": "requête invalide"])
            }
            let name = (object["deviceName"] as? String) ?? "Téléphone"
            guard let token = pairing.complete(code: code, deviceId: deviceId, name: name, now: now()) else {
                return .json(403, ["error": "code invalide ou expiré"])
            }
            return .json(200, ["token": token, "serverName": serverName])

        case ("GET", "/v1/notes"):
            guard pairing.isAuthorized(token: request.bearerToken) else { return .json(401, ["error": "non appairé"]) }
            let encoder = Self.encoder
            let notes = store.allNotes()
            guard let data = try? encoder.encode(notes) else { return .json(400, ["error": "encodage"]) }
            return LANResponse(status: 200, body: data)

        case ("PUT", _) where path.hasPrefix("/v1/notes/"):
            guard pairing.isAuthorized(token: request.bearerToken) else { return .json(401, ["error": "non appairé"]) }
            let uuid = String(path.dropFirst("/v1/notes/".count))
            guard let incoming = try? Self.decoder.decode(CloudNoteDTO.self, from: request.body), incoming.uuid == uuid else {
                return .json(400, ["error": "note invalide"])
            }
            let winner = store.merge(incoming: incoming, now: now())
            guard let data = try? Self.encoder.encode(winner) else { return .json(400, ["error": "encodage"]) }
            return LANResponse(status: 200, body: data)

        default:
            return .json(404, ["error": "introuvable"])
        }
    }

    /// Mêmes conventions de date que la synchro Nextcloud (ISO 8601).
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Serveur réseau

/// Écoute sur le LAN et annonce le service. Démarré seulement si l'utilisateur l'a activé.
final class LANSyncServer {
    static let shared = LANSyncServer()
    static let enabledKey = "lanSyncEnabled"

    let pairing = LANPairing()
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "be.cobaltfilms.alphanote.lan-sync")

    private init() {}

    var isRunning: Bool { listener != nil }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "AlphaNote", type: "_alphanote._tcp")
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("[LANSync] impossible de démarrer : \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private var router: LANSyncRouter {
        LANSyncRouter(pairing: pairing, store: LANDatabaseNoteStore(), serverName: Host.current().localizedName ?? "AlphaNote")
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var collected = buffer
            if let data { collected.append(data) }
            switch LANHTTP.parse(collected) {
            case let .complete(request):
                self.send(self.router.handle(request), on: connection)
            case .invalid:
                self.send(.json(400, ["error": "requête invalide"]), on: connection)
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(connection, buffer: collected)
                }
            }
        }
    }

    private func send(_ response: LANResponse, on connection: NWConnection) {
        connection.send(content: LANHTTP.serialize(response), completion: .contentProcessed { _ in connection.cancel() })
    }
}
