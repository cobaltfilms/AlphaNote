import SwiftUI
import UIKit

/// Réglages iOS : même contenu que SettingsScreen.kt sur Android (apparence,
/// notes, minuteur, Nextcloud, IA, export), sans les mises à jour (pas d'appcast
/// sur iOS). Les clés sont celles de macOS, donc le comportement est identique.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sync = SyncEngine.shared

    @AppStorage(AppSettings.themeKey) private var theme = "system"
    @AppStorage(ColorTheme.storageKey) private var colorTheme = ColorTheme.or.rawValue
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = 17.0
    @AppStorage(AppSettings.listCheckTriggerKey) private var checkTrigger = "/x"
    @AppStorage(AppSettings.autoCleanupKey) private var autoCleanup = true
    @AppStorage(AppSettings.confirmDeleteKey) private var confirmDelete = true
    @AppStorage(AlarmSound.storageKey) private var alarmSound = AlarmSound.minuterie.rawValue

    @AppStorage(SyncEngine.syncEnabledKey) private var syncEnabled = false
    @AppStorage(SyncEngine.syncIntervalMinutesKey) private var syncIntervalMinutes = 5
    @AppStorage(SyncEngine.nextcloudServerURLKey) private var serverURL = ""
    @AppStorage(SyncEngine.nextcloudUsernameKey) private var username = ""
    @State private var appPassword = ""
    @State private var feedback: (message: String, isError: Bool)?
    @State private var isTesting = false
    @State private var alarmPreview = AlarmPlayer()
    @State private var exportFile: ExportFile?

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                notesSection
                timerSection
                syncSection
                Section("Intelligence artificielle") {
                    NavigationLink("IA et serveur JEV") {
                        AISettingsView().navigationTitle("IA")
                    }
                }
                exportSection
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .onAppear(perform: loadStoredPassword)
            .onDisappear { alarmPreview.stop() }
            .sheet(item: $exportFile) { file in
                ActivityView(items: [file.url])
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section("Apparence") {
            Picker("Thème", selection: $theme) {
                Text("Système").tag("system")
                Text("Clair").tag("light")
                Text("Sombre").tag("dark")
            }
            Picker("Couleurs", selection: $colorTheme) {
                ForEach(ColorTheme.allCases) { item in
                    HStack {
                        Circle().fill(Color(hex: item.night.accent)).frame(width: 12, height: 12)
                        Text(item.label)
                    }
                    .tag(item.rawValue)
                }
            }
            .onChange(of: colorTheme) { _, newValue in
                AppIconSwitcher.apply(theme: newValue)
            }
            VStack(alignment: .leading) {
                LabeledContent("Taille du texte", value: "\(Int(fontSize)) pt")
                Slider(value: $fontSize, in: 12...26, step: 1)
            }
        }
    }

    private var notesSection: some View {
        Section {
            LabeledContent("Case cochée") {
                TextField("/x", text: $checkTrigger)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Toggle("Supprimer les notes vides", isOn: $autoCleanup)
            Toggle("Confirmer avant de supprimer", isOn: $confirmDelete)
        } header: {
            Text("Notes")
        } footer: {
            Text("En mode liste, une ligne qui finit par « \(checkTrigger.isEmpty ? "/x" : checkTrigger) » est cochée. Les notes vides disparaissent au retour à la liste.")
        }
    }

    private var timerSection: some View {
        Section {
            Picker("Sonnerie", selection: $alarmSound) {
                // Pas de son système en boucle sur iOS.
                ForEach(AlarmSound.allCases.filter { $0 != .systeme }) { sound in
                    Text(sound.label).tag(sound.rawValue)
                }
            }
            .onChange(of: alarmSound) { _, newValue in
                if let sound = AlarmSound(rawValue: newValue) { alarmPreview.play(sound, loop: false) }
            }
        } header: {
            Text("Minuteur")
        } footer: {
            Text("La sonnerie joue en boucle à la fin d'un compte à rebours. App en arrière-plan : une notification sonne à sa place.")
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("Synchronisation automatique", isOn: $syncEnabled)
                .onChange(of: syncEnabled) { _, enabled in
                    SyncEngine.shared.configureTimer()
                    if enabled { Task { await triggerSync() } }
                }
            TextField("https://cloud.exemple.be", text: $serverURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("Utilisateur", text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            SecureField("Mot de passe d'application", text: $appPassword)
                .textContentType(.password)
            Stepper("Toutes les \(syncIntervalMinutes) min", value: $syncIntervalMinutes, in: 1...120)
                .onChange(of: syncIntervalMinutes) { SyncEngine.shared.configureTimer() }
            HStack {
                Button("Tester") { Task { await testConnection() } }
                    .disabled(isTesting)
                Spacer()
                Button("Synchroniser") { Task { await triggerSync() } }
                    .disabled(!syncEnabled || sync.status == .syncing)
            }
            .buttonStyle(.borderless)
            if let feedback {
                Text(feedback.message)
                    .font(.footnote)
                    .foregroundStyle(feedback.isError ? .red : .green)
            }
            LabeledContent("État", value: statusLabel)
        } header: {
            Text("Nextcloud")
        } footer: {
            Text("Mêmes réglages que sur le Mac et Android : les notes vont dans « AlphaNote/notes » sur ton Nextcloud. Le mot de passe reste dans le trousseau de l'iPhone.")
        }
    }

    private var exportSection: some View {
        Section {
            Button("Exporter en JSON") { export(json: true) }
            Button("Exporter en Markdown") { export(json: false) }
        } header: {
            Text("Export")
        } footer: {
            Text("JSON : même format que la synchro. Markdown : un seul fichier, une note par section.")
        }
    }

    private var statusLabel: String {
        switch sync.status {
        case .idle: return syncEnabled ? "En attente" : "Désactivée"
        case .syncing: return "Synchronisation…"
        case .success(let date): return "OK à \(date.formatted(date: .omitted, time: .shortened))"
        case .error(let message): return message
        }
    }

    // MARK: - Nextcloud

    private func loadStoredPassword() {
        appPassword = (try? KeychainService.shared.readPassword(serverURL: serverURL, username: username)) ?? ""
    }

    private func persistPassword() throws {
        let server = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, !user.isEmpty, !appPassword.isEmpty else { return }
        try KeychainService.shared.savePassword(appPassword, serverURL: server, username: user)
    }

    private func testConnection() async {
        feedback = nil
        isTesting = true
        defer { isTesting = false }
        do {
            try persistPassword()
            try await SyncEngine.shared.testConnection()
            feedback = ("Connexion réussie.", false)
        } catch {
            feedback = (error.localizedDescription, true)
        }
    }

    private func triggerSync() async {
        do {
            feedback = nil
            try persistPassword()
            SyncEngine.shared.runManualSync()
        } catch {
            feedback = (error.localizedDescription, true)
        }
    }

    // MARK: - Export

    private func export(json: Bool) {
        let notes = Note.fetchAll()
        let directory = FileManager.default.temporaryDirectory
        do {
            let url: URL
            if json {
                url = directory.appendingPathComponent("AlphaNote-export.json")
                let encoder = CloudJSONCoder.makeEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(notes.map(CloudNoteDTO.init(note:))).write(to: url, options: .atomic)
            } else {
                url = directory.appendingPathComponent("AlphaNote-export.md")
                let markdown = notes.map { "# \(NoteFormatting.displayTitle($0))\n\n\($0.content)" }
                    .joined(separator: "\n\n---\n\n")
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            }
            exportFile = ExportFile(url: url)
        } catch {
            feedback = (error.localizedDescription, true)
        }
    }
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
