import Foundation

/// iOS-adapted AI service — uses CoreMLInferenceEngine instead of MLX.
actor AIService: AIServiceProtocol {
    static let shared = AIService()

    private let coreMLEngine: AIInferenceEngineProtocol
    private let fallbackEngine: AIInferenceEngineProtocol

    init(
        coreMLEngine: AIInferenceEngineProtocol = CoreMLInferenceEngine(),
        fallbackEngine: AIInferenceEngineProtocol = HeuristicFallbackInferenceEngine()
    ) {
        self.coreMLEngine = coreMLEngine
        self.fallbackEngine = fallbackEngine
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
        let requestedProfile = AIModelRegistry.effectiveProfile(userModelID: selectedModelID, qualityTier: quality)
        let swapUsedGB = AIModelDiagnostics.swapUsedGB()
        let conservativeMode = UserDefaults.standard.object(forKey: AISettingsKeys.conservativePolicyEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: AISettingsKeys.conservativePolicyEnabled)
        let companionAwarenessEnabled = resolvedCompanionAwarenessEnabled()
        let companionLLMRunning = companionAwarenessEnabled && AIModelDiagnostics.companionLLMStatus().isDetected
        let resolvedProfile = requestedProfile
        let effectiveModelID = customModelID.isEmpty ? resolvedProfile.id : customModelID

        let maxTokensSetting = UserDefaults.standard.integer(forKey: AISettingsKeys.maxTokens)
        let requestedMaxTokens = maxTokensSetting == 0 ? resolvedProfile.recommendedMaxTokens : maxTokensSetting
        let maxTokens = AIModelRegistry.memorySafeMaxTokens(
            requested: requestedMaxTokens,
            profile: resolvedProfile,
            swapUsedGB: swapUsedGB,
            conservativeMode: conservativeMode,
            companionLLMRunning: companionLLMRunning
        )

        let prompt = AIPromptBuilder.prompt(for: task, note: note, context: context)
        let options = AIRequestOptions(
            temperature: 0.2,
            maxTokens: maxTokens,
            topP: 0.9,
            stop: []
        )

        do {
            let raw = try await collect(
                stream: coreMLEngine.generate(
                    prompt: prompt,
                    system: AIPromptBuilder.systemPrompt,
                    modelID: effectiveModelID,
                    options: options
                ),
                timeout: 120
            )
            return try AIResponseParser.parse(raw, for: task)
        } catch {
            // On iOS, heuristics are the default fallback
            let allowFallback = UserDefaults.standard.object(forKey: AISettingsKeys.allowFallbackHeuristics) as? Bool ?? true
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

    /// Simple model availability check (no download on iOS for now).
    func verifyModel(modelID: String) async -> Result<String, AIError> {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .failure(.internalFailure("ID de modèle vide."))
        }

        let status = AIModelDiagnostics.localStatus(for: normalized)
        if status.isDownloaded {
            return .success("Modèle Core ML disponible: \(normalized)")
        }
        return .failure(.modelUnavailable)
    }

    nonisolated func localModelStatus(modelID: String) -> AIModelLocalStatus {
        AIModelDiagnostics.localStatus(for: modelID)
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
            if case let .internalFailure(message) = aiError {
                return .internalFailure(AIModelDiagnostics.summarizedError(message))
            }
            return aiError
        }
        if error is CancellationError {
            return .cancelled
        }
        return .internalFailure(AIModelDiagnostics.summarizedError(error.localizedDescription))
    }

    private func resolvedCompanionAwarenessEnabled() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AISettingsKeys.companionAwarenessEnabled) != nil {
            return defaults.bool(forKey: AISettingsKeys.companionAwarenessEnabled)
        }
        if defaults.object(forKey: AISettingsKeys.cotypistAwarenessEnabledLegacy) != nil {
            return defaults.bool(forKey: AISettingsKeys.cotypistAwarenessEnabledLegacy)
        }
        return false // iOS: no companion LLM awareness by default
    }
}

struct AIFeatureGate {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AISettingsKeys.enabled)
    }
}
