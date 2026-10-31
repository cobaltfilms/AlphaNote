import SwiftUI

/// Réglages IA. En tête, les moteurs réellement en service (modèle local ou
/// serveur JEV pour classer, Apple Intelligence ou JEV pour les formules) ;
/// le serveur JEV est facultatif, et ce qu'il reçoit reste consultable dans
/// les détails techniques.
struct AISettingsView: View {
    @AppStorage(AISettingsKeys.enabled) private var aiEnabled = false
    @AppStorage(AISettingsKeys.jevURL) private var jevURL = AISettingsKeys.jevURLDefault
    @AppStorage(AISettingsKeys.jevDelaiMs) private var jevDelaiMs = AISettingsKeys.jevDelaiMsDefault
    @AppStorage(AISettingsKeys.formulaDraftEnabled) private var formulaDraftEnabled = true

    @AppStorage(JEVAccessToken.clientIDKey) private var accessClientID = ""
    @State private var accessSecret = ""
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    @State private var showTechnicalDetails = false

    var body: some View {
        Form {
            Section {
                engineRow("Classement des demandes", systemImage: aiEnabled ? "server.rack" : "cpu",
                          value: aiEnabled ? "Serveur JEV" : "Modèle local",
                          detail: aiEnabled
                            ? "Le serveur classe la demande ; s'il ne répond pas, le modèle de cet appareil prend le relais."
                            : "Un petit modèle sur cet appareil classe la demande (calcul, liste, minuteur, code, texte), hors ligne.")
                engineRow("Rédaction des formules", systemImage: formulaEngine.symbol,
                          value: formulaEngine.name, detail: formulaEngine.detail)
            } header: {
                Text("Moteurs en service")
            } footer: {
                HelpNote("Seule la phrase de la demande quitte l'appareil, et seulement vers un serveur JEV si vous en utilisez un : jamais le contenu des notes. La recherche reste locale.")
            }

            Section {
                HelpToggle("Laisser l'IA rédiger les formules", isOn: $formulaDraftEnabled,
                           help: "En mode math, une demande en mots (« aire d'un cercle de rayon 3 ») devient une formule, calculée par la note.")
                    .disabled(!aiEnabled && !AppleFormulaDrafter.isAvailable)
            } header: {
                Text("Rédaction des formules")
            } footer: {
                HelpNote("Une formule rédigée n'est gardée que si la note sait la calculer, et elle est marquée « formule proposée par l'IA, à vérifier ».")
            }

            Section {
                HelpToggle("Utiliser un serveur JEV", isOn: $aiEnabled,
                           help: "Pour classer les demandes avec votre propre serveur (et rédiger les formules sans Apple Intelligence).")

                if aiEnabled {
                    HelpTextField("URL du serveur", text: $jevURL, prompt: "https://jev.exemple.com",
                                  help: "Serveur de décision JEV (POST /v1/decision).")

                    HelpTextField("Jeton d'accès (ID)", text: $accessClientID, prompt: "….access",
                                  help: "Client ID du jeton de service Cloudflare Access. Vide pour un serveur sur le réseau local ou Tailscale.")
                        .onChange(of: accessClientID) { _, _ in saveAccessToken() }
                    LabeledContent {
                        SecureField("Secret", text: $accessSecret)
                            .onSubmit(saveAccessToken)
                            .onChange(of: accessSecret) { _, _ in saveAccessToken() }
                    } label: {
                        FieldLabel("Jeton d'accès (secret)", help: "Client Secret du jeton, gardé dans le trousseau.")
                    }

                    LabeledContent {
                        Stepper("\(jevDelaiMs / 1000) s", value: $jevDelaiMs, in: 2_000...60_000, step: 1_000)
                    } label: {
                        FieldLabel("Délai", help: "Temps maximal d'attente de la réponse du serveur.")
                    }

                    HStack {
                        Button(isTesting ? "Test en cours…" : "Tester le serveur") {
                            Task { await testServer() }
                        }
                        .disabled(isTesting)
                        Spacer()
                    }

                    if let statusMessage {
                        Label(statusMessage, systemImage: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(statusIsError ? .red : .green)
                    }
                }
            } header: {
                Text("Serveur JEV (facultatif)")
            }

            if aiEnabled {
                Section {
                    DisclosureGroup("Ce que reçoit le serveur", isExpanded: $showTechnicalDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Classement — POST /v1/decision").font(.caption.weight(.semibold))
                            schemaCard
                            Text("Formules — POST /v1/chat/completions").font(.caption.weight(.semibold))
                            Text(FormulaDraftFeature.systemPrompt)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 6)
                    }
                } header: {
                    Text("Détails techniques")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { accessSecret = JEVAccessToken.storedSecret(clientID: accessClientID) }
    }

    /// Qui rédige les formules, dans l'ordre réellement suivi par FormulaDraftFeature.
    private var formulaEngine: (name: String, symbol: String, detail: String) {
        if !formulaDraftEnabled {
            return ("Désactivée", "nosign", "Les demandes en mots ne deviennent pas des formules.")
        }
        if AppleFormulaDrafter.isAvailable {
            return ("Apple Intelligence", "sparkles",
                    "Sur cet appareil, hors ligne." + (aiEnabled ? " Le serveur JEV sert de secours." : ""))
        }
        if aiEnabled {
            return ("Serveur JEV", "server.rack", "Apple Intelligence n'est pas disponible sur cet appareil.")
        }
        return ("Indisponible", "exclamationmark.circle",
                "Il faut Apple Intelligence (Mac M1 ou plus récent, iPhone 15 Pro ou plus récent) ou un serveur JEV.")
    }

    private func engineRow(_ title: String, systemImage: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Label(value, systemImage: systemImage)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
    private func saveAccessToken() {
        JEVAccessToken.save(clientID: accessClientID, secret: accessSecret)
    }

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

        // Même jeton d'accès que les vraies demandes (JEVClient.config()).
        let config = JEVConfig(url: url, delaiMs: jevDelaiMs > 0 ? jevDelaiMs : AISettingsKeys.jevDelaiMsDefault,
                               access: JEVAccessToken.load())
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
