import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            KeywordSettingsView()
                .tabItem { Label("Keywords", systemImage: "tag") }

            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }

            UpdatesSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 600, height: 520)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("hotkeyEnabled") private var hotkeyEnabled = true
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("autoCleanup") private var autoCleanup = true

    var body: some View {
        Form {
            Section {
                HelpToggle("Enable global hotkey (⌥A)", isOn: $hotkeyEnabled,
                           help: "Ouvre et ferme la fenêtre de note depuis n'importe quelle app.")
                HelpToggle("Show in Dock", isOn: $showInDock,
                           help: "Affiche AlphaNote dans le Dock.")
                HelpToggle("Show in Menu Bar", isOn: $showInMenuBar,
                           help: "Ajoute l'icône A| dans la barre des menus.")
                HelpToggle("Auto-cleanup empty notes", isOn: $autoCleanup,
                           help: "Supprime automatiquement les notes restées vides.")
            }
        }
        .padding(20)
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("fontSize") private var fontSize: Double = 14

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Picker("Theme", selection: $theme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                } label: {
                    FieldLabel("Theme", help: "Apparence claire, sombre, ou synchronisée au système.")
                }

                LabeledContent {
                    HStack {
                        Slider(value: $fontSize, in: 10...24, step: 1)
                            .frame(width: 180)
                        Text("\(Int(fontSize)) pt")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } label: {
                    FieldLabel("Font size", help: "Taille du texte dans l'éditeur de note.")
                }
            }
        }
        .padding(20)
    }
}

// MARK: - Keywords

struct KeywordSettingsView: View {
    @AppStorage("keywordMath") private var keywordMath = "math"
    @AppStorage("keywordList") private var keywordList = "list"
    @AppStorage("keywordCode") private var keywordCode = "code"
    @AppStorage("keywordTimer") private var keywordTimer = "timer"
    @AppStorage("listCheckTrigger") private var listCheckTrigger = "/x"
    @AppStorage("listModeShortcutKey") private var listModeShortcutKey = "l"
    @AppStorage("listModeShortcutModifiers") private var listModeShortcutModifiers = "commandShift"

    var body: some View {
        Form {
            Section {
                HelpTextField("Math keyword", text: $keywordMath,
                              help: "Premier mot qui bascule la note en calculatrice.")
                HelpTextField("List keyword", text: $keywordList,
                              help: "Premier mot qui bascule la note en checklist.")
                HelpTextField("Code keyword", text: $keywordCode,
                              help: "Premier mot qui bascule la note en éditeur de code.")
                HelpTextField("Timer keyword", text: $keywordTimer,
                              help: "Premier mot qui bascule la note en minuteur.")
            } header: {
                Text("Mode keywords")
            } footer: {
                HelpNote("Le mot-clé se place en première ligne de la note.")
            }

            Section {
                HelpTextField("List check trigger", text: $listCheckTrigger,
                              help: "Suffixe qui coche un élément de liste (ex. /x).")

                LabeledContent {
                    HStack {
                        Picker("List shortcut", selection: $listModeShortcutModifiers) {
                            Text("⌘⇧").tag("commandShift")
                            Text("⌘⌥").tag("commandOption")
                            Text("⌘⌃").tag("commandControl")
                            Text("⌘").tag("command")
                        }
                        .labelsHidden()
                        .frame(width: 120)

                        TextField("Key", text: $listModeShortcutKey)
                            .labelsHidden()
                            .frame(width: 40)
                            .multilineTextAlignment(.center)
                            .onChange(of: listModeShortcutKey) {
                                let filtered = listModeShortcutKey
                                    .lowercased()
                                    .filter { $0.isLetter || $0.isNumber }
                                listModeShortcutKey = String(filtered.prefix(1))
                                if listModeShortcutKey.isEmpty {
                                    listModeShortcutKey = "l"
                                }
                            }
                    }
                } label: {
                    FieldLabel("Convert to list", help: "Raccourci qui convertit la note active en liste.")
                }
            } header: {
                Text("List")
            }
        }
        .padding(20)
    }
}

// MARK: - Advanced

struct AdvancedSettingsView: View {
    @ObservedObject private var syncEngine = SyncEngine.shared

    @AppStorage(DatabaseManager.databaseLocationUserDefaultsKey)
    private var databaseLocation = DatabaseManager.defaultDatabaseDirectoryPath()
    @AppStorage(SyncEngine.syncEnabledKey) private var syncEnabled = false
    @AppStorage(SyncEngine.syncIntervalMinutesKey) private var syncIntervalMinutes = 5
    @AppStorage(SyncEngine.nextcloudServerURLKey) private var nextcloudServerURL = ""
    @AppStorage(SyncEngine.nextcloudUsernameKey) private var nextcloudUsername = ""

    @State private var appPassword = ""
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var isTestingConnection = false
    @State private var nextcloudNotesFolder = "Notes"
    @State private var isImportingNextcloudNotes = false
    @State private var isImportingAppleNotes = false

    var body: some View {
        Form {
            Section {
                HelpTextField("Database location", text: $databaseLocation,
                              help: "Dossier où AlphaNote range sa base SQLite.")
            } header: {
                Text("Database")
            }

            Section {
                HelpToggle("Enable cloud sync", isOn: $syncEnabled,
                           help: "Synchronise les notes via WebDAV (Nextcloud).")
                    .onChange(of: syncEnabled) {
                        SyncEngine.shared.configureTimer()
                        if syncEnabled {
                            SyncEngine.shared.runManualSync()
                        }
                    }

                HelpTextField("Server URL", text: $nextcloudServerURL, prompt: "https://…",
                              help: "Adresse de votre instance Nextcloud.")
                HelpTextField("Username", text: $nextcloudUsername,
                              help: "Identifiant Nextcloud.")

                LabeledContent {
                    SecureField("App password", text: $appPassword)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                } label: {
                    FieldLabel("App password", help: "Mot de passe applicatif, stocké dans le trousseau.")
                }

                LabeledContent {
                    Stepper("\(syncIntervalMinutes) min", value: $syncIntervalMinutes, in: 1...60)
                } label: {
                    FieldLabel("Sync interval", help: "Fréquence de la synchronisation automatique.")
                }

                HStack {
                    Button(isTestingConnection ? "Testing…" : "Test connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTestingConnection)

                    Button("Sync now") {
                        Task { await triggerManualSync() }
                    }
                    .disabled(!syncEnabled)

                    Spacer()
                }

                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(statusColor)
            } header: {
                Text("Cloud Sync (Nextcloud)")
            }

            Section {
                HelpTextField("Nextcloud Notes folder", text: $nextcloudNotesFolder,
                              help: "Dossier distant où lire/écrire les notes.")

                HStack {
                    Button(isImportingNextcloudNotes ? "Importing Nextcloud Notes…" : "Import Nextcloud Notes") {
                        Task { await importNextcloudNotes() }
                    }
                    .disabled(isImportingNextcloudNotes || isImportingAppleNotes)

                    Button(isImportingAppleNotes ? "Importing Apple Notes…" : "Import Apple Notes") {
                        Task { await importAppleNotes() }
                    }
                    .disabled(isImportingAppleNotes || isImportingNextcloudNotes)
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.callout)
                        .foregroundStyle(feedbackIsError ? .red : .green)
                }
            } header: {
                Text("Import")
            } footer: {
                HelpNote("Les imports ignorent automatiquement les doublons.")
            }

            HStack {
                Spacer()
                Button("Reveal in Finder") {
                    let resolvedPath = DatabaseManager.resolveDatabaseDirectoryPath(databaseLocation)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: resolvedPath)
                }
                Button("Export Data") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.init(filenameExtension: "json")!].compactMap { $0 }
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        exportData(to: url)
                    }
                }
            }
        }
        .padding(20)
        .onAppear {
            loadStoredPassword()
            syncIntervalMinutes = max(syncIntervalMinutes, 1)
        }
    }

    private func exportData(to url: URL) {
        let notes = Note.fetchAll()
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: url)
        } catch {
            print("[Settings] Export failed: \(error)")
        }
    }

    private var statusLine: String {
        if let feedbackMessage {
            return feedbackMessage
        }

        switch syncEngine.status {
        case .idle:
            return "Status: idle"
        case .syncing:
            return "Status: syncing…"
        case let .success(date):
            return "Status: success (\(date.formatted(date: .abbreviated, time: .shortened)))"
        case let .error(message):
            return "Status: error – \(message)"
        }
    }

    private var statusColor: Color {
        if feedbackMessage != nil {
            return feedbackIsError ? .red : .green
        }
        if case .error = syncEngine.status {
            return .red
        }
        return .secondary
    }

    @MainActor
    private func loadStoredPassword() {
        do {
            let loaded = try KeychainService.shared.readPassword(serverURL: nextcloudServerURL, username: nextcloudUsername)
            appPassword = loaded ?? ""
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }

    @MainActor
    private func persistPasswordIfPossible() throws {
        let server = nextcloudServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = nextcloudUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !server.isEmpty, !username.isEmpty else { return }
        guard !appPassword.isEmpty else { return }
        try KeychainService.shared.savePassword(appPassword, serverURL: server, username: username)
    }

    @MainActor
    private func testConnection() async {
        feedbackMessage = nil
        feedbackIsError = false
        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            try persistPasswordIfPossible()
            try await SyncEngine.shared.testConnection()
            feedbackMessage = "Connection successful."
            feedbackIsError = false
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }

    @MainActor
    private func triggerManualSync() async {
        do {
            feedbackMessage = nil
            feedbackIsError = false
            try persistPasswordIfPossible()
            SyncEngine.shared.runManualSync()
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }

    @MainActor
    private func importNextcloudNotes() async {
        feedbackMessage = nil
        feedbackIsError = false
        isImportingNextcloudNotes = true
        defer { isImportingNextcloudNotes = false }

        do {
            try persistPasswordIfPossible()
            let password = try resolveNextcloudPasswordForImport()
            let report = try await NoteImportService.shared.importNextcloudNotes(
                serverURL: nextcloudServerURL,
                username: nextcloudUsername,
                password: password,
                folderPath: nextcloudNotesFolder
            )
            feedbackMessage = report.summary
            feedbackIsError = false
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }

    @MainActor
    private func importAppleNotes() async {
        feedbackMessage = nil
        feedbackIsError = false
        isImportingAppleNotes = true
        defer { isImportingAppleNotes = false }

        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try NoteImportService.shared.importAppleNotes()
            }.value
            if report.scanned == 0 {
                feedbackMessage = "\(report.summary) Si vous attendiez des notes, ouvrez Apple Notes une fois, laissez la sync finir, puis relancez l'import."
            } else {
                feedbackMessage = report.summary
            }
            feedbackIsError = false
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }

    @MainActor
    private func resolveNextcloudPasswordForImport() throws -> String {
        let inline = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inline.isEmpty {
            return inline
        }

        let server = nextcloudServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = nextcloudUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = try KeychainService.shared.readPassword(serverURL: server, username: username)
        guard let stored, !stored.isEmpty else {
            throw SyncConfigurationError.missingPassword
        }
        return stored
    }
}

// MARK: - Updates

struct UpdatesSettingsView: View {
    @ObservedObject private var updater = UpdateManager.shared
    @AppStorage(AISettingsKeys.updateAppcastURL) private var appcastURL = ""

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(AppVersion.current)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                } label: {
                    FieldLabel("Version", help: "Version d'AlphaNote actuellement installée.")
                }

                HelpTextField("Appcast URL", text: $appcastURL, prompt: "https://…/appcast.json",
                              help: "Adresse JSON décrivant la dernière version. Vide = pas de canal configuré.")

                HStack {
                    Button(updater.phase == .checking ? "Checking…" : "Check for Updates") {
                        updater.check(userInitiated: true)
                    }
                    .disabled(updater.phase == .checking || appcastURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }

                HelpNote("AlphaNote vérifie une version plus récente, télécharge le paquet, le vérifie, puis se remplace et se relance. Rien n'est installé sans correspondance d'identité.")
            } header: {
                Text("Mises à jour")
            }

            if let feedError = updater.feedConfigurationError {
                Section {
                    Label(feedError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(20)
        .sheet(isPresented: $updater.showingSheet) {
            UpdateSheet(updater: updater)
        }
    }
}
