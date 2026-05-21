import XCTest
@testable import AlphaNote

final class AIServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: AISettingsKeys.enabled)
        UserDefaults.standard.set(AIQualityTier.balanced.rawValue, forKey: AISettingsKeys.qualityMode)
        UserDefaults.standard.set(AIModelProfile.gemma34B.id, forKey: AISettingsKeys.selectedModelID)
        UserDefaults.standard.set(400, forKey: AISettingsKeys.maxTokens)
        UserDefaults.standard.set(true, forKey: AISettingsKeys.allowFallbackHeuristics)
        UserDefaults.standard.removeObject(forKey: AISettingsKeys.customModelID)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AISettingsKeys.enabled)
        UserDefaults.standard.removeObject(forKey: AISettingsKeys.qualityMode)
        UserDefaults.standard.removeObject(forKey: AISettingsKeys.selectedModelID)
        UserDefaults.standard.removeObject(forKey: AISettingsKeys.customModelID)
        UserDefaults.standard.removeObject(forKey: AISettingsKeys.maxTokens)
        UserDefaults.standard.removeObject(forKey: AISettingsKeys.allowFallbackHeuristics)
        super.tearDown()
    }

    func testSummarizeReturnsText() async throws {
        let service = AIService(
            mlxEngine: MockEngine(output: "Résumé court de la note"),
            fallbackEngine: MockEngine(output: "fallback")
        )

        let note = Note(content: "AlphaNote est une app de notes locale")
        let result = try await service.run(task: .summarize, note: note, context: .empty)
        XCTAssertEqual(result.text, "Résumé court de la note")
    }

    func testExtractActionsParsesJSON() async throws {
        let json = """
        {"actions":[{"title":"Préparer release","owner":"Paul","deadline":"2026-05-30","priority":"high"}]}
        """

        let service = AIService(
            mlxEngine: MockEngine(output: json),
            fallbackEngine: MockEngine(output: "fallback")
        )

        let note = Note(content: "TODO: préparer la release avec Paul avant le 30 mai")
        let result = try await service.run(task: .extractActions, note: note, context: .empty)
        XCTAssertTrue(result.text.contains("Préparer release"))
        XCTAssertEqual(result.metadata["format"], "json_actions")
    }

    func testFallbackEngineIsUsedWhenPrimaryFails() async throws {
        let service = AIService(
            mlxEngine: MockFailingEngine(),
            fallbackEngine: MockEngine(output: "fallback output")
        )

        let note = Note(content: "Contenu")
        let result = try await service.run(task: .rewrite(style: .clear), note: note, context: .empty)
        XCTAssertEqual(result.text, "fallback output")
        XCTAssertEqual(result.metadata["engine"], "fallback")
    }
}

private struct MockEngine: AIInferenceEngineProtocol {
    let output: String

    func generate(
        prompt: String,
        system: String?,
        modelID: String,
        options: AIRequestOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(output)
            continuation.finish()
        }
    }
}

private struct MockFailingEngine: AIInferenceEngineProtocol {
    func generate(
        prompt: String,
        system: String?,
        modelID: String,
        options: AIRequestOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AIError.modelUnavailable)
        }
    }
}
