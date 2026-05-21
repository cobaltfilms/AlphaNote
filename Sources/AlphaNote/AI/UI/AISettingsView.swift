import SwiftUI

struct AISettingsView: View {
    @AppStorage(AISettingsKeys.enabled) private var aiEnabled = false
    @AppStorage(AISettingsKeys.selectedModelID) private var selectedModelID = AIModelProfile.gemma34B.id
    @AppStorage(AISettingsKeys.customModelID) private var customModelID = ""
    @AppStorage(AISettingsKeys.qualityMode) private var qualityMode = AIQualityTier.balanced.rawValue
    @AppStorage(AISettingsKeys.maxTokens) private var maxTokens = 700
    @AppStorage(AISettingsKeys.allowFallbackHeuristics) private var allowFallbackHeuristics = false
    @State private var isTestingModel = false
    @State private var testMessage: String?
    @State private var testIsError = false

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
                    Text(profile.displayName).tag(profile.id)
                }
            }

            TextField("ID modèle MLX custom (optionnel)", text: $customModelID)

            Stepper("Limite tokens: \(maxTokens)", value: $maxTokens, in: 128...2048, step: 64)
            Toggle("Fallback heuristique si MLX indisponible", isOn: $allowFallbackHeuristics)
            HStack {
                Button(isTestingModel ? "Test en cours..." : "Tester le modèle") {
                    Task { await runModelTest() }
                }
                .disabled(isTestingModel)
                Spacer()
            }

            if let testMessage {
                Text(testMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(testIsError ? .red : .green)
            }

            Text("Si le modèle n'est pas encore téléchargé, MLX peut le récupérer automatiquement depuis Hugging Face via son ID. Pour un premier test, Qwen 3 1.7B (MLX) démarre généralement plus vite.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var effectiveModelID: String {
        let custom = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return custom
        }
        return selectedModelID
    }

    private func runModelTest() async {
        isTestingModel = true
        defer { isTestingModel = false }

        let result = await AIService.shared.verifyModel(modelID: effectiveModelID)
        switch result {
        case let .success(message):
            testMessage = message
            testIsError = false
        case let .failure(error):
            if error == .timeout {
                testMessage = "Le test a expiré. Au premier lancement, le téléchargement du modèle peut prendre plusieurs minutes. Réessaie dans un instant."
            } else {
                testMessage = error.localizedDescription
            }
            testIsError = true
        }
    }
}
