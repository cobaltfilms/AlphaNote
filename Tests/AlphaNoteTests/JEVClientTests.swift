import XCTest
@testable import AlphaNote

private struct FakeJEVTransport: JEVTransport {
    let data: Data
    func post(url: URL, body: Data, delaiMs: Int) async throws -> Data { data }
}

private struct ThrowingJEVTransport: JEVTransport {
    let error: Error
    func post(url: URL, body: Data, delaiMs: Int) async throws -> Data { throw error }
}

private func jevJSON(_ results: [[String: Any]]) -> Data {
    try! JSONSerialization.data(withJSONObject: ["results": results])
}

final class JEVClientTests: XCTestCase {
    private let config = JEVConfig(url: "http://test.local:8096", delaiMs: 5_000)

    // MARK: - Schéma

    func testEmptySchemaIsRejected() {
        XCTAssertNotNil(JEVClient.verifierSchema([:]))
    }

    func testFieldWithoutDescriptionIsRejected() {
        let schema: JEVSchema = ["mode": .string(choices: ["math", "plain"], description: "  ")]
        XCTAssertNotNil(JEVClient.verifierSchema(schema))
    }

    func testEnumWithTooFewChoicesIsRejected() {
        let schema: JEVSchema = ["mode": .string(choices: ["math"], description: "un mode")]
        XCTAssertNotNil(JEVClient.verifierSchema(schema))
    }

    func testUnboundedIntegerIsRejected() {
        let schema: JEVSchema = ["score": .integer(description: "score", minimum: 10, maximum: 10)]
        XCTAssertNotNil(JEVClient.verifierSchema(schema))
    }

    func testValidSchemaPasses() {
        XCTAssertNil(JEVClient.verifierSchema(ModeRoutingFeature.schema))
    }

    // MARK: - Décision

    func testMissingConfigIsAFrankError() async {
        UserDefaults.standard.removeObject(forKey: AISettingsKeys.jevURL)
        let outcome = await JEVClient.decider(
            instructions: "x",
            schema: ModeRoutingFeature.schema,
            fragments: ["12 * 8"],
            transport: FakeJEVTransport(data: jevJSON([["decision": ["mode": "math"]]]))
        )
        guard case let .erreur(message) = outcome else {
            return XCTFail("Attendu .erreur, reçu \(outcome)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testHappyPathReturnsDecision() async {
        let outcome = await JEVClient.decider(
            config: config,
            instructions: ModeRoutingFeature.instructions,
            schema: ModeRoutingFeature.schema,
            fragments: ["12 * 8"],
            transport: FakeJEVTransport(data: jevJSON([["decision": ["mode": "math"]]]))
        )
        guard case let .ok(decisions) = outcome else {
            return XCTFail("Attendu .ok, reçu \(outcome)")
        }
        XCTAssertEqual(decisions.first?["mode"], .string("math"))
    }

    func testIncompleteResponseIsAnError() async {
        let outcome = await JEVClient.decider(
            config: config,
            instructions: ModeRoutingFeature.instructions,
            schema: ModeRoutingFeature.schema,
            fragments: ["12 * 8", "courses: riz, poulet"],
            transport: FakeJEVTransport(data: jevJSON([["decision": ["mode": "math"]]]))
        )
        guard case .erreur = outcome else {
            return XCTFail("Une réponse incomplète doit être un échec, reçu \(outcome)")
        }
    }

    func testUnreachableServerIsAnError() async {
        let outcome = await JEVClient.decider(
            config: config,
            instructions: ModeRoutingFeature.instructions,
            schema: ModeRoutingFeature.schema,
            fragments: ["12 * 8"],
            transport: ThrowingJEVTransport(error: JEVTransportError.http(status: 503))
        )
        guard case .erreur = outcome else {
            return XCTFail("Attendu .erreur, reçu \(outcome)")
        }
    }

    // MARK: - Lecture de la réponse

    func testLireReponseIgnoresValuesOutsideEnumOrType() {
        let brut: [String: Any] = ["results": [["decision": ["mode": "pas_un_mode", "inconnu": 1]]]]
        let decisions = JEVClient.lireReponse(brut, schema: ModeRoutingFeature.schema, attendus: 1)
        XCTAssertNil(decisions.first?["mode"])
    }

    func testLireReponseCoercesTypesAndKeepsOrder() {
        let schema: JEVSchema = [
            "mode": .string(choices: ["math", "plain"], description: "mode"),
            "sûr": .boolean(description: "confiance"),
            "score": .integer(description: "score", minimum: 0, maximum: 100)
        ]
        let brut: [String: Any] = [
            "results": [
                ["decision": ["mode": "math", "sûr": true, "score": 42.0]],
                ["decision": ["mode": "plain"]]
            ]
        ]
        let decisions = JEVClient.lireReponse(brut, schema: schema, attendus: 2)
        XCTAssertEqual(decisions.count, 2)
        XCTAssertEqual(decisions[0]["mode"], .string("math"))
        XCTAssertEqual(decisions[0]["sûr"], .boolean(true))
        XCTAssertEqual(decisions[0]["score"], .integer(42))
        XCTAssertEqual(decisions[1]["mode"], .string("plain"))
        XCTAssertNil(decisions[1]["score"])
    }

    // MARK: - Routage de mode

    func testModeRoutingFallsBackToKeywordsWhenJEVUnconfigured() async {
        UserDefaults.standard.set(true, forKey: AISettingsKeys.enabled)
        UserDefaults.standard.removeObject(forKey: AISettingsKeys.jevURL)
        let decision = await ModeRoutingFeature().route(question: "12 * 8", noteKeyword: nil)
        XCTAssertEqual(decision.mode, .math)
        XCTAssertEqual(decision.source, .motsCles)
    }
}
