import Foundation

struct AIFeatureGate {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AISettingsKeys.enabled)
    }
}

actor AIService: AIServiceProtocol {
    static let shared = AIService()

    private let engine: AIInferenceEngineProtocol

    init(engine: AIInferenceEngineProtocol = CoreMLInferenceEngine()) {
        self.engine = engine
    }

    func run(task: AITask, note: Note, context: AIContext) async throws -> AIResult {
        guard AIFeatureGate.isEnabled else {
            throw AIError.disabled
        }

        let qualityRaw = UserDefaults.standard.string(forKey: AISettingsKeys.qualityMode) ?? AIQualityTier.fast.rawValue
        let quality = AIQualityTier(rawValue: qualityRaw) ?? .fast
        let selectedModelID = UserDefaults.standard.string(forKey: AISettingsKeys.selectedModelID)
        let customModelID = UserDefaults.standard
            .string(forKey: AISettingsKeys.customModelID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profile = AIModelRegistry.effectiveProfile(userModelID: selectedModelID, qualityTier: quality)
        let modelID = customModelID.isEmpty ? profile.id : customModelID

        let maxTokensSetting = UserDefaults.standard.integer(forKey: AISettingsKeys.maxTokens)
        let maxTokens = maxTokensSetting == 0 ? profile.recommendedMaxTokens : maxTokensSetting

        let prompt = AIPromptBuilder.prompt(for: task, note: note, context: context)
        let options = AIRequestOptions(
            temperature: 0.2,
            maxTokens: maxTokens,
            topP: 0.9,
            stop: []
        )

        do {
            let raw = try await collect(
                stream: engine.generate(
                    prompt: prompt,
                    system: AIPromptBuilder.systemPrompt,
                    modelID: modelID,
                    options: options
                ),
                timeout: 120
            )
            return try AIResponseParser.parse(raw, for: task)
        } catch {
            // Fallback heuristique
            let allowFallback = UserDefaults.standard.object(forKey: AISettingsKeys.allowFallbackHeuristics) as? Bool ?? false
            guard allowFallback, task != .semanticAnswer else {
                throw mapError(error)
            }
            let raw = try await collect(
                stream: HeuristicFallbackInferenceEngine().generate(
                    prompt: prompt, system: AIPromptBuilder.systemPrompt,
                    modelID: "heuristic", options: options
                ),
                timeout: 4
            )
            var result = try AIResponseParser.parse(raw, for: task)
            result = AIResult(text: result.text, metadata: result.metadata.merging(["engine": "fallback"]) { $1 })
            return result
        }
    }

    private func collect(stream: AsyncThrowingStream<String, Error>, timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var buffer = ""
                for try await chunk in stream {
                    if Task.isCancelled { throw AIError.cancelled }
                    buffer.append(chunk)
                    if !buffer.hasSuffix("\n") { buffer.append("\n") }
                }
                return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AIError.timeout
            }
            let first = try await group.next() ?? ""
            group.cancelAll()
            return first
        }
    }

    private func mapError(_ error: Error) -> AIError {
        if let aiError = error as? AIError { return aiError }
        if error is CancellationError { return .cancelled }
        return .internalFailure(error.localizedDescription)
    }
}

// MARK: - Core ML Inference Engine (placeholder)
final class CoreMLInferenceEngine: AIInferenceEngineProtocol {
    func generate(
        prompt: String,
        system: String?,
        modelID: String,
        options: AIRequestOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // TODO: Implémenter le bridge Core ML quand les modèles
                // Gemma 4 seront disponibles en Core ML.
                // Pour l'instant, on bascule sur le fallback heuristique.
                continuation.finish(throwing: AIError.modelUnavailable)
            }
        }
    }
}

// MARK: - Fallback heuristique (fonctionne sans modèle)
final class HeuristicFallbackInferenceEngine: AIInferenceEngineProtocol {
    func generate(
        prompt: String,
        system: String?,
        modelID: String,
        options: AIRequestOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let response: String
            if prompt.contains("Résumer") {
                response = "[Résumé non disponible — modèle IA requis]"
            } else if prompt.contains("Réécrire") {
                response = prompt.components(separatedBy: "Contenu:")
                    .last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } else {
                response = ""
            }
            continuation.yield(response)
            continuation.finish()
        }
    }
}
