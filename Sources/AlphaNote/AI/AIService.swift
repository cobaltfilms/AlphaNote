import Foundation

struct AIFeatureGate {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AISettingsKeys.enabled)
    }
}

actor AIService: AIServiceProtocol {
    static let shared = AIService()

    private let mlxEngine: AIInferenceEngineProtocol
    private let fallbackEngine: AIInferenceEngineProtocol

    init(
        mlxEngine: AIInferenceEngineProtocol = MLXSwiftInferenceEngine(),
        fallbackEngine: AIInferenceEngineProtocol = HeuristicFallbackInferenceEngine()
    ) {
        self.mlxEngine = mlxEngine
        self.fallbackEngine = fallbackEngine
    }

    func run(task: AITask, note: Note, context: AIContext) async throws -> AIResult {
        guard AIFeatureGate.isEnabled else {
            throw AIError.disabled
        }

        let qualityRaw = UserDefaults.standard.string(forKey: AISettingsKeys.qualityMode) ?? AIQualityTier.balanced.rawValue
        let quality = AIQualityTier(rawValue: qualityRaw) ?? .balanced

        let selectedModelID = UserDefaults.standard.string(forKey: AISettingsKeys.selectedModelID)
        let customModelID = UserDefaults.standard
            .string(forKey: AISettingsKeys.customModelID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profile = AIModelRegistry.effectiveProfile(userModelID: selectedModelID, qualityTier: quality)
        let effectiveModelID = customModelID.isEmpty ? profile.id : customModelID

        let maxTokensSetting = UserDefaults.standard.integer(forKey: AISettingsKeys.maxTokens)
        let maxTokens = max(128, maxTokensSetting == 0 ? profile.recommendedMaxTokens : maxTokensSetting)

        let prompt = AIPromptBuilder.prompt(for: task, note: note, context: context)
        let options = AIRequestOptions(
            temperature: 0.2,
            maxTokens: maxTokens,
            topP: 0.9,
            stop: []
        )

        do {
            let raw = try await collect(
                stream: mlxEngine.generate(
                    prompt: prompt,
                    system: AIPromptBuilder.systemPrompt,
                    modelID: effectiveModelID,
                    options: options
                ),
                timeout: 120
            )
            return try AIResponseParser.parse(raw, for: task)
        } catch {
            let allowFallback = UserDefaults.standard.object(forKey: AISettingsKeys.allowFallbackHeuristics) as? Bool ?? false
            guard allowFallback, task != .semanticAnswer else {
                throw mapError(error)
            }

            let raw = try await collect(
                stream: fallbackEngine.generate(
                    prompt: prompt,
                    system: AIPromptBuilder.systemPrompt,
                    modelID: "heuristic",
                    options: options
                ),
                timeout: 4
            )

            var result = try AIResponseParser.parse(raw, for: task)
            result = AIResult(text: result.text, metadata: result.metadata.merging(["engine": "fallback"]) { $1 })
            return result
        }
    }

    func verifyModel(modelID: String) async -> Result<String, AIError> {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .failure(.internalFailure("ID de modèle vide."))
        }

        do {
            let raw = try await collect(
                stream: mlxEngine.generate(
                    prompt: "Réponds uniquement OK",
                    system: "Test de disponibilité modèle local.",
                    modelID: normalized,
                    options: AIRequestOptions(temperature: 0, maxTokens: 12, topP: 1, stop: [])
                ),
                timeout: 300
            )
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.invalidOutput)
            }
            return .success("Modèle prêt: \(normalized)")
        } catch {
            return .failure(mapError(error))
        }
    }

    private func collect(stream: AsyncThrowingStream<String, Error>, timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var buffer = ""
                for try await chunk in stream {
                    if Task.isCancelled {
                        throw AIError.cancelled
                    }
                    buffer.append(chunk)
                    if !buffer.hasSuffix("\n") {
                        buffer.append("\n")
                    }
                }
                return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            group.addTask {
                let ns = UInt64(timeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw AIError.timeout
            }

            let first = try await group.next() ?? ""
            group.cancelAll()
            return first
        }
    }

    private func mapError(_ error: Error) -> AIError {
        if let aiError = error as? AIError {
            return aiError
        }
        if error is CancellationError {
            return .cancelled
        }
        return .internalFailure(error.localizedDescription)
    }
}
