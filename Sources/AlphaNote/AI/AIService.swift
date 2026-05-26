import Foundation

struct AIFeatureGate {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AISettingsKeys.enabled)
    }
}

actor AIService: AIServiceProtocol {
    static let shared = AIService()

    private let ggufEngine: AIInferenceEngineProtocol
    private let fallbackEngine: AIInferenceEngineProtocol

    init(
        ggufEngine: AIInferenceEngineProtocol = LlamaCppInferenceEngine(),
        fallbackEngine: AIInferenceEngineProtocol = HeuristicFallbackInferenceEngine()
    ) {
        self.ggufEngine = ggufEngine
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
                stream: ggufEngine.generate(
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

        let modelPath = GGUFDownloadManager.localPath(for: AIModelRegistry.profile(for: normalized))
        if !FileManager.default.fileExists(atPath: modelPath) {
            return .failure(.internalFailure("Modèle non téléchargé. Clique sur « Télécharger / Préparer »."))
        }

        do {
            let raw = try await collect(
                stream: ggufEngine.generate(
                    prompt: "Réponds uniquement OK",
                    system: "Test.",
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

    func prepareModel(
        modelID: String,
        onProgress: @escaping @Sendable (String, Double?) -> Void
    ) async -> Result<String, AIError> {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .failure(.internalFailure("ID de modèle vide."))
        }

        let profile = AIModelRegistry.profile(for: normalized)
        let modelPath = GGUFDownloadManager.localPath(for: profile)

        if FileManager.default.fileExists(atPath: modelPath) {
            return .success("Modèle déjà téléchargé: \(profile.displayName)")
        }

        do {
            try await GGUFDownloadManager.shared.download(modelID: normalized, onProgress: onProgress)
            return .success("Modèle téléchargé: \(profile.displayName)")
        } catch {
            return .failure(mapError(error))
        }
    }

    func unloadCurrentModel() async {}

    func localModelStatus(modelID: String) -> AIModelLocalStatus {
        let profile = AIModelRegistry.profile(for: modelID)

        let customPath = UserDefaults.standard
            .string(forKey: AISettingsKeys.ggufCustomPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customPath.isEmpty, FileManager.default.fileExists(atPath: customPath) {
            return modelStatusAtPath(customPath, modelID: modelID)
        }

        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let cotypistPath = home + "/Library/Application Support/app.cotypist.Cotypist/Models/gemma-4-E2B-i1-Q4_K_M.gguf"
        if profile.id == "gemma-4-e2b", FileManager.default.fileExists(atPath: cotypistPath) {
            return modelStatusAtPath(cotypistPath, modelID: modelID)
        }

        let path = GGUFDownloadManager.localPath(for: profile)
        return modelStatusAtPath(path, modelID: modelID)
    }

    private func modelStatusAtPath(_ path: String, modelID: String) -> AIModelLocalStatus {
        let fm = FileManager.default
        let isDownloaded = fm.fileExists(atPath: path)
        var size: Int64 = 0
        var updatedAt: Date? = nil
        if let attrs = try? fm.attributesOfItem(atPath: path) {
            size = (attrs[.size] as? Int64) ?? 0
            updatedAt = attrs[.modificationDate] as? Date
        }
        return AIModelLocalStatus(
            modelID: modelID,
            isDownloaded: isDownloaded,
            cachePath: path,
            cachedSizeBytes: size,
            updatedAt: updatedAt
        )
    }

    nonisolated func runtimeInfo(modelID: String) -> AIManagedRuntimeInfo {
        if LlamaCppInferenceEngine.isAvailable {
            let path = LlamaCppInferenceEngine.serverPath ?? "llama-server"
            return AIManagedRuntimeInfo(
                mode: "llamacpp",
                pythonPath: nil,
                torchVersion: nil,
                isTorchCompatible: true,
                hasMLXLMModule: true,
                hasMLXVLMModule: true,
                summary: "llama.cpp détecté: \(path)"
            )
        }
        return AIManagedRuntimeInfo(
            mode: "indisponible",
            pythonPath: nil,
            torchVersion: nil,
            isTorchCompatible: false,
            hasMLXLMModule: false,
            hasMLXVLMModule: false,
            summary: "llama.cpp non détecté."
        )
    }

    func repairRuntimeWithUV(onProgress: @escaping @Sendable (String) -> Void) async -> Result<String, AIError> {
        if LlamaCppInferenceEngine.isAvailable {
            return .success("llama.cpp détecté, prêt à l'emploi.")
        }
        return .failure(.internalFailure("llama.cpp introuvable. Installe-le avec: brew install llama.cpp"))
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
        return true
    }
}
