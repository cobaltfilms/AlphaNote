import XCTest
@testable import AlphaNote

/// Magasin de notes en mémoire : remplace la base GRDB pour tester le routage seul.
private final class FakeNoteStore: LANNoteStore {
    var notes: [String: CloudNoteDTO] = [:]

    func allNotes() -> [CloudNoteDTO] { Array(notes.values) }

    func merge(incoming: CloudNoteDTO, now: Date) -> CloudNoteDTO {
        guard let local = notes[incoming.uuid] else {
            notes[incoming.uuid] = incoming
            return incoming
        }
        let winner = SyncEngine.resolveConflict(local, incoming)
        notes[incoming.uuid] = winner
        return winner
    }
}

final class LANSyncTests: XCTestCase {

    private var defaults: UserDefaults!
    private var pairing: LANPairing!
    private var store: FakeNoteStore!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "LANSyncTests-\(UUID().uuidString)")!
        pairing = LANPairing(defaults: defaults)
        store = FakeNoteStore()
    }

    private func router() -> LANSyncRouter {
        LANSyncRouter(pairing: pairing, store: store, serverName: "Mac de test", now: { self.t0 })
    }

    private func request(_ method: String, _ path: String, token: String? = nil, body: Data = Data()) -> LANRequest {
        var headers = ["content-length": String(body.count)]
        if let token { headers["authorization"] = "Bearer \(token)" }
        return LANRequest(method: method, path: path, headers: headers, body: body)
    }

    private func pairedToken() throws -> String {
        let code = pairing.beginPairing(now: t0)
        let body = try JSONSerialization.data(withJSONObject: ["code": code, "deviceId": "phone-1", "deviceName": "Pixel"])
        let response = router().handle(request("POST", "/v1/pair", body: body))
        XCTAssertEqual(response.status, 200)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        return try XCTUnwrap(object["token"] as? String)
    }

    private func dto(_ uuid: String, content: String, updatedAt: Date, device: String = "phone-1") -> CloudNoteDTO {
        let json: [String: Any] = [
            "schemaVersion": 1, "uuid": uuid, "content": content, "keyword": "", "title": content,
            "position": 0, "isPinned": false, "archived": false, "isDeleted": false,
            "createdAt": ISO8601DateFormatter().string(from: t0),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
            "lastModifiedByDeviceId": device
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! LANSyncRouter.decoder.decode(CloudNoteDTO.self, from: data)
    }

    // MARK: HTTP

    func testParseWaitsForFullBody() {
        let head = "PUT /v1/notes/x HTTP/1.1\r\nContent-Length: 5\r\n\r\nab"
        XCTAssertEqual(LANHTTP.parse(Data(head.utf8)), .incomplete)
        let full = head + "cde"
        guard case let .complete(parsed) = LANHTTP.parse(Data(full.utf8)) else { return XCTFail("requête attendue") }
        XCTAssertEqual(parsed.method, "PUT")
        XCTAssertEqual(String(decoding: parsed.body, as: UTF8.self), "abcde")
    }

    func testParseReadsBearerToken() {
        let raw = "GET /v1/notes HTTP/1.1\r\nAuthorization: Bearer abc123\r\n\r\n"
        guard case let .complete(parsed) = LANHTTP.parse(Data(raw.utf8)) else { return XCTFail() }
        XCTAssertEqual(parsed.bearerToken, "abc123")
    }

    func testParseRejectsOversizedAndMalformed() {
        XCTAssertEqual(LANHTTP.parse(Data("GET\r\n\r\n".utf8)), .invalid)
        XCTAssertEqual(LANHTTP.parse(Data("PUT / HTTP/1.1\r\nContent-Length: -4\r\n\r\n".utf8)), .invalid)
    }

    // MARK: Appairage

    func testPairingIssuesTokenOnlyWithRightCode() throws {
        let code = pairing.beginPairing(now: t0)
        XCTAssertEqual(code.count, 6)
        XCTAssertNil(pairing.complete(code: "000000x", deviceId: "p", name: "n", now: t0))
        XCTAssertNotNil(pairing.complete(code: code, deviceId: "p", name: "n", now: t0))
        // Code à usage unique.
        XCTAssertNil(pairing.complete(code: code, deviceId: "p2", name: "n", now: t0))
    }

    func testPairingCodeExpires() {
        let code = pairing.beginPairing(now: t0)
        let later = t0.addingTimeInterval(LANPairing.codeLifetime + 1)
        XCTAssertNil(pairing.complete(code: code, deviceId: "p", name: "n", now: later))
    }

    func testPairingLocksAfterTooManyWrongAttempts() {
        let code = pairing.beginPairing(now: t0)
        let wrong = code == "111111" ? "222222" : "111111"
        for _ in 0..<LANPairing.maxAttempts {
            XCTAssertNil(pairing.complete(code: wrong, deviceId: "p", name: "n", now: t0))
        }
        // Même le bon code ne passe plus : il faut générer un nouveau code.
        XCTAssertNil(pairing.complete(code: code, deviceId: "p", name: "n", now: t0))
    }

    func testStoredTokenIsHashed() throws {
        let token = try pairedToken()
        let stored = try XCTUnwrap(defaults.data(forKey: LANPairing.pairedDevicesKey))
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains(token))
        XCTAssertTrue(pairing.isAuthorized(token: token))
        XCTAssertFalse(pairing.isAuthorized(token: "faux"))
        XCTAssertFalse(pairing.isAuthorized(token: nil))
    }

    func testUnpairRevokesToken() throws {
        let token = try pairedToken()
        pairing.unpair(deviceId: "phone-1")
        XCTAssertFalse(pairing.isAuthorized(token: token))
    }

    // MARK: Routage

    func testNotesRequireToken() {
        XCTAssertEqual(router().handle(request("GET", "/v1/notes")).status, 401)
    }

    func testInfoIsPublicAndNamesTheMac() throws {
        let response = router().handle(request("GET", "/v1/info"))
        XCTAssertEqual(response.status, 200)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        XCTAssertEqual(object["name"] as? String, "Mac de test")
    }

    func testPushThenPullRoundTripsANote() throws {
        let token = try pairedToken()
        let note = dto("note-1", content: "courses", updatedAt: t0)
        let body = try LANSyncRouter.encoder.encode(note)

        let put = router().handle(request("PUT", "/v1/notes/note-1", token: token, body: body))
        XCTAssertEqual(put.status, 200)
        XCTAssertEqual(store.notes["note-1"], note)

        let list = router().handle(request("GET", "/v1/notes", token: token))
        let notes = try LANSyncRouter.decoder.decode([CloudNoteDTO].self, from: list.body)
        XCTAssertEqual(notes, [note])
    }

    func testPutKeepsMoreRecentLocalVersion() throws {
        let token = try pairedToken()
        store.notes["note-1"] = dto("note-1", content: "version Mac", updatedAt: t0.addingTimeInterval(60))
        let older = dto("note-1", content: "version téléphone", updatedAt: t0)
        let body = try LANSyncRouter.encoder.encode(older)

        let response = router().handle(request("PUT", "/v1/notes/note-1", token: token, body: body))
        let winner = try LANSyncRouter.decoder.decode(CloudNoteDTO.self, from: response.body)
        XCTAssertEqual(winner.content, "version Mac")
        XCTAssertEqual(store.notes["note-1"]?.content, "version Mac")
    }

    func testPutRejectsMismatchedUUID() throws {
        let token = try pairedToken()
        let body = try LANSyncRouter.encoder.encode(dto("autre", content: "x", updatedAt: t0))
        XCTAssertEqual(router().handle(request("PUT", "/v1/notes/note-1", token: token, body: body)).status, 400)
    }
}
