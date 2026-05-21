import SwiftUI

struct AISettingsView: View {
    @AppStorage(AISettingsKeys.enabled) private var aiEnabled = false
    @AppStorage(AISettingsKeys.selectedModelID) private var selectedModelID = AIModelProfile.qwen31_7B.id
    @AppStorage(AISettingsKeys.customModelID) private var customModelID = ""
    @AppStorage(AISettingsKeys.qualityMode) private var qualityMode = AIQualityTier.fast.rawValue
    @AppStorage(AISettingsKeys.maxTokens) private var maxTokens = 500
    @AppStorage(AISettingsKeys.allowFallbackHeuristics) private var allowFallbackHeuristics = false
    @AppStorage(AISettingsKeys.conservativePolicyEnabled) private var conservativePolicyEnabled = true
    @AppStorage(AISettingsKeys.companionAwarenessEnabled) private var companionAwarenessEnabled = true
    @State private var isPreparingModel = false
    @State private var isTestingModel = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var downloadProgress: Double?
    @State private var downloadDetailLine = ""
    @State private var localStatus: AIModelLocalStatus?
    @State private var previousEffectiveModelID = ""
    @State private var isSwitchingModel = false
    @State private var isRepairingRuntime = false
    @State private var machineMemoryGB = AIModelDiagnostics.physicalMemoryGB()
    @State private var swapUsedGB: Double = 0
    @State private var companionStatus = AICompanionLLMStatus(isDetected: false, detectedSources: [], estimatedResidentGB: 0)
    @State private var diagnosticsRefreshTask: Task<Void, Never>?
    @State private var runtimeInfo = AIManagedRuntimeInfo(
        mode: "pending",
        pythonPath: nil,
        torchVersion: nil,
        isTorchCompatible: true,
        hasMLXLMModule: false,
        summary: "Analyse du runtime IA en cours..."
    )

    var body: some View {
        Form {
            Toggle("Activer l'IA locale", isOn: $aiEnabled)

            Picker("Qualité", selection: $qualityMode) {
                ForEach(AIQualityTier.allCases, id: \.rawValue) { tier in
                    Text(tier.label).tag(tier.rawValue)
                }
            }

            Picker("Modèle", selection: $selectedModelID) {
                ForEach(AIModelRegistry.allProfiles, id: \.id) { profile in
                    Text("\(profile.displayName) • \(profile.displayFormat) • \(profile.memoryHint)").tag(profile.id)
                }
            }

            TextField("ID modèle MLX custom (optionnel)", text: $customModelID)
                .onSubmit {
                    Task { await handleModelChangeIfNeeded() }
                }

            Stepper(
                "Limite tokens (mode notes): \(maxTokens) / max \(dynamicMaxTokens)",
                value: $maxTokens,
                in: 64...dynamicMaxTokens,
                step: 64
            )
            Toggle("Fallback heuristique si MLX indisponible", isOn: $allowFallbackHeuristics)
            Toggle("Mode conservateur mémoire (recommandé)", isOn: $conservativePolicyEnabled)
            Toggle("Optimiser cohabitation avec autres apps IA locales", isOn: $companionAwarenessEnabled)
            Text("Optimisé pour notes (stable): contexte court, mémoire maîtrisée, qualité suffisante pour résumé/réécriture/actions.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let profile = currentProfile {
                Text("Profil: \(profile.stabilityTier.label)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Téléchargement estimé: ~\(String(format: "%.1f", profile.estimatedDownloadGB)) GB")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if machineMemoryGB < profile.recommendedMinMemoryGB {
                    Text("Ce modèle peut fonctionner sur \(machineMemoryGB) GB, mais avec contexte court. Tokens automatiquement plafonnés pour limiter la pression mémoire.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            Text(AIModelRegistry.machineRecommendation(physicalMemoryGB: machineMemoryGB))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if companionAwarenessEnabled && companionStatus.isDetected {
                Text("Autre runtime IA local détecté (\(companionStatus.detectedSources.joined(separator: ", ")), ~\(String(format: "%.1f", companionStatus.estimatedResidentGB)) GB résidents). AlphaNote réduit automatiquement la charge pour limiter la pression mémoire.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            if conservativePolicyEnabled && swapUsedGB >= 2 {
                Text("Mode conservateur actif: swap détecté (\(String(format: "%.1f", swapUsedGB)) GB). Limite de contexte réduite pour éviter les blocages.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            if conservativePolicyEnabled && shouldSuggestFallbackToSmallModel {
                HStack(spacing: 8) {
                    Text("Mémoire très tendue: mieux vaut repasser sur un petit modèle MLX.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                    Button("Revenir au modèle par défaut") {
                        switchToDefaultSmallModel()
                    }
                }
            }

            if let localStatus {
                Text(localStatus.isDownloaded ? "Modèle téléchargé localement" : "Modèle non téléchargé")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(localStatus.isDownloaded ? .green : .secondary)
                Text("Cache: \(AIModelDiagnostics.formatSize(localStatus.cachedSizeBytes))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let updatedAt = localStatus.updatedAt {
                    Text("Dernière activité: \(formatDate(updatedAt))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Text("Emplacement: \(localStatus.cachePath)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(runtimeInfo.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if !runtimeInfo.isTorchCompatible || !runtimeInfo.hasMLXLMModule {
                Text("Runtime IA incomplet (torch/mlx-lm). Réparation conseillée.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            if let progress = downloadProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text(downloadDetailLine.isEmpty ? "Téléchargement en cours..." : downloadDetailLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if isSwitchingModel {
                Text("Changement de modèle: libération de la mémoire en cours...")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(isPreparingModel ? "Préparation..." : "Télécharger / Préparer") {
                    Task { await prepareModel() }
                }
                .disabled(isPreparingModel || isTestingModel || isRepairingRuntime)
                Button(isTestingModel ? "Vérification..." : "Vérifier le chargement") {
                    Task { await runLoadCheck() }
                }
                .disabled(isPreparingModel || isTestingModel || isRepairingRuntime)
                Button(isRepairingRuntime ? "Réparation..." : "Réparer runtime IA") {
                    Task { await repairRuntime() }
                }
                .disabled(isPreparingModel || isTestingModel || isRepairingRuntime)
                Spacer()
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusIsError ? .red : .green)
            }

            Text("Par défaut, AlphaNote reste sur des petits modèles pour être accessible sur la plupart des Mac. Les modèles lourds restent accessibles ici, avec estimation machine et état de téléchargement.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Note: « Q4_K_M » est un nom GGUF (llama.cpp), pas un format MLX. Ici les modèles sont affichés en format MLX (ex: MLX 4-bit).")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .onAppear {
            migrateCompanionAwarenessSettingIfNeeded()
            previousEffectiveModelID = effectiveModelID
            refreshLocalStatus()
            refreshRuntimeInfo()
            refreshMachineMemorySignalsAsync()
            clampMaxTokensForNotesProfile()
        }
        .onChange(of: selectedModelID) {
            Task { await handleModelChangeIfNeeded() }
            refreshMachineMemorySignalsAsync()
            clampMaxTokensForNotesProfile()
        }
        .onChange(of: customModelID) {
            clampMaxTokensForNotesProfile()
        }
        .onChange(of: qualityMode) {
            applyQualityDefaultIfNeeded()
            refreshMachineMemorySignalsAsync()
            clampMaxTokensForNotesProfile()
        }
        .onChange(of: conservativePolicyEnabled) {
            refreshMachineMemorySignalsAsync()
            clampMaxTokensForNotesProfile()
        }
        .onChange(of: companionAwarenessEnabled) {
            refreshMachineMemorySignalsAsync()
            clampMaxTokensForNotesProfile()
        }
        .onDisappear {
            diagnosticsRefreshTask?.cancel()
            diagnosticsRefreshTask = nil
        }
    }

    private var effectiveModelID: String {
        let custom = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return custom
        }
        return selectedModelID
    }

    private var currentProfile: AIModelProfile? {
        AIModelRegistry.allProfiles.first(where: { $0.id == effectiveModelID })
    }

    private var dynamicMaxTokens: Int {
        let profile = currentProfile ?? AIModelProfile.qwen31_7B
        return AIModelRegistry.memorySafeMaxTokens(
            requested: 2048,
            profile: profile,
            swapUsedGB: swapUsedGB,
            conservativeMode: conservativePolicyEnabled,
            companionLLMRunning: companionAwarenessEnabled && companionStatus.isDetected
        )
    }

    private func clampMaxTokensForNotesProfile() {
        let maxAllowed = dynamicMaxTokens
        if maxTokens > maxAllowed {
            maxTokens = maxAllowed
        }
        if maxTokens < 64 {
            maxTokens = 64
        }
    }

    private func refreshMachineMemorySignalsAsync() {
        diagnosticsRefreshTask?.cancel()
        diagnosticsRefreshTask = Task(priority: .utility) {
            let snapshot = await Task.detached(priority: .utility) { () -> (Int, Double, AICompanionLLMStatus) in
                let memory = AIModelDiagnostics.physicalMemoryGB()
                let swap = AIModelDiagnostics.swapUsedGB()
                let companion = AIModelDiagnostics.companionLLMStatus()
                return (memory, swap, companion)
            }.value
            guard !Task.isCancelled else { return }
            machineMemoryGB = snapshot.0
            swapUsedGB = snapshot.1
            companionStatus = snapshot.2
        }
    }

    private var shouldSuggestFallbackToSmallModel: Bool {
        guard let profile = currentProfile else { return false }
        if swapUsedGB >= 16 && profile.isHeavyForNotes {
            return true
        }
        if companionAwarenessEnabled && companionStatus.isDetected && profile.isHeavyForNotes {
            return true
        }
        return false
    }

    private func switchToDefaultSmallModel() {
        selectedModelID = AIModelProfile.qwen31_7B.id
        customModelID = ""
        statusMessage = "Retour automatique proposé appliqué: petit modèle MLX par défaut."
        statusIsError = false
    }

    private func applyQualityDefaultIfNeeded() {
        guard customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard let tier = AIQualityTier(rawValue: qualityMode) else { return }
        selectedModelID = AIModelRegistry.defaultProfile(for: tier).id
    }

    private func migrateCompanionAwarenessSettingIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AISettingsKeys.companionAwarenessEnabled) == nil,
              defaults.object(forKey: AISettingsKeys.cotypistAwarenessEnabledLegacy) != nil else {
            return
        }
        let legacyValue = defaults.bool(forKey: AISettingsKeys.cotypistAwarenessEnabledLegacy)
        defaults.set(legacyValue, forKey: AISettingsKeys.companionAwarenessEnabled)
        companionAwarenessEnabled = legacyValue
    }

    private func refreshLocalStatus() {
        localStatus = AIModelDiagnostics.localStatus(for: effectiveModelID)
    }

    private func refreshRuntimeInfo() {
        Task.detached(priority: .utility) {
            let info = AIService.shared.runtimeInfo()
            await MainActor.run {
                runtimeInfo = info
            }
        }
    }

    private func handleModelChangeIfNeeded() async {
        let next = effectiveModelID
        guard !next.isEmpty, next != previousEffectiveModelID else { return }
        isSwitchingModel = true
        await AIService.shared.unloadCurrentModel()
        previousEffectiveModelID = next
        statusMessage = "Ancien modèle déchargé. Tu peux préparer le nouveau modèle."
        statusIsError = false
        downloadProgress = nil
        downloadDetailLine = ""
        refreshLocalStatus()
        refreshRuntimeInfo()
        isSwitchingModel = false
    }

    private func prepareModel() async {
        isPreparingModel = true
        statusMessage = nil
        statusIsError = false
        downloadProgress = nil
        downloadDetailLine = ""
        defer {
            isPreparingModel = false
            refreshLocalStatus()
            refreshRuntimeInfo()
        }

        let result = await AIService.shared.prepareModel(modelID: effectiveModelID) { line, percent in
            Task { @MainActor in
                downloadDetailLine = line
                if let percent {
                    downloadProgress = percent
                }
            }
        }

        switch result {
        case let .success(message):
            downloadProgress = 1.0
            statusMessage = "Préparation terminée. \(message)"
            statusIsError = false
        case let .failure(error):
            downloadProgress = nil
            downloadDetailLine = ""
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func runLoadCheck() async {
        isTestingModel = true
        defer {
            isTestingModel = false
            refreshRuntimeInfo()
        }

        let result = await AIService.shared.verifyModel(modelID: effectiveModelID)
        switch result {
        case let .success(message):
            statusMessage = message
            statusIsError = false
        case let .failure(error):
            if error == .timeout {
                statusMessage = "La vérification a expiré. Si le modèle vient d'être téléchargé, attends quelques instants puis réessaie."
            } else {
                statusMessage = error.localizedDescription
            }
            statusIsError = true
        }
    }

    private func repairRuntime() async {
        isRepairingRuntime = true
        statusMessage = nil
        statusIsError = false
        downloadProgress = nil
        downloadDetailLine = ""
        defer {
            isRepairingRuntime = false
            refreshRuntimeInfo()
        }

        let result = await AIService.shared.repairRuntimeWithUV { line in
            Task { @MainActor in
                downloadDetailLine = line
            }
        }

        switch result {
        case let .success(message):
            statusMessage = message
            statusIsError = false
        case let .failure(error):
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
