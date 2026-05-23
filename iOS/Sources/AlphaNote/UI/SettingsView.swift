import SwiftUI

struct SettingsView: View {
    @AppStorage("fontSize") private var fontSize: Double = 14
    @AppStorage("autoCleanup") private var autoCleanup = true
    @AppStorage("aiEnabled") private var aiEnabled = false
    @AppStorage("syncEnabled") private var syncEnabled = false

    @State private var selectedQuality = AIQualityTier.fast

    var body: some View {
        NavigationStack {
            Form {
                Section("Général") {
                    Toggle("Nettoyage auto des notes vides", isOn: $autoCleanup)
                    HStack {
                        Text("Taille de police")
                        Slider(value: $fontSize, in: 10...24, step: 1)
                        Text("\(Int(fontSize))")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Intelligence Artificielle") {
                    Toggle("Activer l'IA locale", isOn: $aiEnabled)

                    if aiEnabled {
                        Picker("Qualité", selection: $selectedQuality) {
                            ForEach(AIQualityTier.allCases, id: \.self) { tier in
                                Text(tier.label).tag(tier)
                            }
                        }

                        Text("Les modèles Gemma 4 E2B et E4B sont recommandés. Téléchargement automatique au premier usage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Synchronisation") {
                    Toggle("Activer la synchro Nextcloud", isOn: $syncEnabled)
                }

                Section("À propos") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.0 (iOS)")
                            .foregroundStyle(.secondary)
                    }
                    Text("AlphaNote — Cobalt Films")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        // Ferme la sheet
                    }
                }
            }
        }
    }
}
