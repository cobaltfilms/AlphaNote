import SwiftUI

/// Réglages IA réduits au strict contrat JEV : un serveur de décision qui
/// CLASSE la demande dans un mode, jamais une IA qui rédige. Tout est
/// transparent : on voit l'URL, le délai, et le schéma exact envoyé.
struct AISettingsView: View {
    @AppStorage(AISettingsKeys.enabled) private var aiEnabled = false
    @AppStorage(AISettingsKeys.jevURL) private var jevURL = AISettingsKeys.jevURLDefault
    @AppStorage(AISettingsKeys.jevDelaiMs) private var jevDelaiMs = AISettingsKeys.jevDelaiMsDefault

    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section {
                HelpToggle("Activer le routage de mode IA", isOn: $aiEnabled,
                           help: "Le serveur ne fait que classer la demande dans un mode. Il ne rédige jamais.")
            } header: {
                Text("Routage de mode")
            } footer: {
                HelpNote("Désactivé, AlphaNote reste sur les mots-clés déterministes.")
            }

            Section {
                HelpTextField("URL du serveur", text: $jevURL, prompt: "http://192.168.3.169:8096",
                              help: "Serveur de décision JEV (POST /v1/decision).")

                LabeledContent {
                    Stepper("\(jevDelaiMs) ms", value: $jevDelaiMs, in: 2_000...60_000, step: 1_000)
                } label: {
                    FieldLabel("Délai", help: "Temps maximal d'attente de la réponse du serveur.")
                }

                HStack {
                    Button(isTesting ? "Test en cours…" : "Tester le serveur") {
                        Task { await testServer() }
                    }
                    .disabled(isTesting || !aiEnabled)

                    Spacer()
                }

                if let statusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        Text(statusMessage)
                    }
                    .font(.callout)
                    .foregroundStyle(statusIsError ? .red : .green)
                }

                HelpNote("Serveur injoignable ? AlphaNote bascule sur les mots-clés et l'écran l'affiche. Rien n'est silencieux.")
            } header: {
                Text("Serveur JEV")
            }

            Section {
                schemaCard
            } header: {
                Text("Transparence — schéma envoyé")
            } footer: {
                HelpNote("C'est exactement ce que le serveur reçoit : un seul champ « mode », enum, avec la description de chaque mode. La recherche sémantique reste 100 % locale (embeddings hash-64, hors-ligne).")
            }
        }
        .formStyle(.grouped)
    }

    private var schemaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ModeRoutingFeature.schema.keys.sorted()), id: \.self) { nom in
                let champ = ModeRoutingFeature.schema[nom]!
                HStack(spacing: 8) {
                    Text(nom)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(typeLabel(champ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(champ.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func typeLabel(_ champ: JEVField) -> String {
        switch champ {
        case let .string(choices, _):
            return "enum { \(choices.joined(separator: ", ")) }"
        case .boolean:
            return "boolean"
        case let .integer(_, minimum, maximum):
            return "integer [\(minimum)…\(maximum)]"
        case let .number(_, minimum, maximum):
            return "number [\(minimum)…\(maximum)]"
        }
    }

    @MainActor
    private func testServer() async {
        statusMessage = nil
        statusIsError = false
        isTesting = true
        defer { isTesting = false }

        let url = jevURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            statusMessage = "Aucune URL de serveur configurée."
            statusIsError = true
            return
        }

        let config = JEVConfig(url: url, delaiMs: jevDelaiMs > 0 ? jevDelaiMs : AISettingsKeys.jevDelaiMsDefault)
        switch await JEVClient.decider(
            config: config,
            instructions: ModeRoutingFeature.instructions,
            schema: ModeRoutingFeature.schema,
            fragments: ["minuteur 5 minutes"]
        ) {
        case .ok:
            statusMessage = "Serveur joignable — décision rendue."
            statusIsError = false
        case let .erreur(message):
            statusMessage = message
            statusIsError = true
        }
    }
}
