import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Général", systemImage: "gear") }
            AppearanceSettingsView()
                .tabItem { Label("Apparence", systemImage: "paintbrush") }
            SyncSettingsView()
                .tabItem { Label("Synchronisation", systemImage: "arrow.triangle.2.circlepath.icloud") }
            AISettingsView()
                .tabItem { Label("IA", systemImage: "sparkles") }
            UpdatesSettingsView()
                .tabItem { Label("Mises à jour", systemImage: "arrow.down.circle") }
            AdvancedSettingsView()
                .tabItem { Label("Avancé", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 620, height: 560)
    }
}

// MARK: - Général

struct GeneralSettingsView: View {
    @AppStorage(HotkeySettings.enabledKey) private var hotkeyEnabled = true
    @AppStorage(HotkeySettings.keyCodeKey) private var hotkeyKeyCode = Int(HotkeySettings.keyCode(forCharacter: "a") ?? 0)
    @AppStorage(HotkeySettings.modifiersKey) private var hotkeyModifiers = Int(HotkeySettings.defaultModifiers.rawValue)
    @AppStorage(NoteWindowController.alwaysOnTopKey) private var alwaysOnTop = true
    @AppStorage(AppDelegate.showInDockKey) private var showInDock = true
    @AppStorage(AppDelegate.showInMenuBarKey) private var showInMenuBar = true
    @AppStorage(AppDelegate.autoCleanupKey) private var autoCleanup = true

    var body: some View {
        Form {
            Section {
                HelpToggle("Raccourci global", isOn: $hotkeyEnabled,
                           help: "Ouvre et ferme la fenêtre de notes depuis n'importe quelle app.")
                LabeledContent {
                    HStack(spacing: 10) {
                        HotkeyRecorderView(
                            keyCode: $hotkeyKeyCode,
                            modifiers: Binding(
                                get: { UInt(hotkeyModifiers) },
                                set: { hotkeyModifiers = Int($0) }
                            )
                        )
                        .frame(width: 150, height: 26)
                        .disabled(!hotkeyEnabled)
                        Button("Par défaut (⌥A)") {
                            hotkeyKeyCode = Int(HotkeySettings.defaultKeyCode)
                            hotkeyModifiers = Int(HotkeySettings.defaultModifiers.rawValue)
                        }
                        .controlSize(.small)
                        .disabled(!hotkeyEnabled)
                    }
                } label: {
                    FieldLabel("Combinaison", help: "Cliquez puis appuyez sur la combinaison voulue (au moins un modificateur).")
                }
            } header: {
                Text("Raccourci")
            } footer: {
                HelpNote("Échap cache aussi la fenêtre quand aucun volet n'est ouvert.")
            }

            Section {
                HelpToggle("Toujours au premier plan", isOn: $alwaysOnTop,
                           help: "La fenêtre flotte au-dessus des autres apps.")
                HelpToggle("Afficher dans le Dock", isOn: $showInDock,
                           help: "Sinon, AlphaNote vit uniquement dans la barre des menus.")
                HelpToggle("Afficher dans la barre des menus", isOn: $showInMenuBar,
                           help: "Icône dans la barre des menus. Reste visible si le Dock est masqué.")
                    .disabled(!showInDock)
                HelpToggle("Supprimer les notes vides à la fermeture", isOn: $autoCleanup,
                           help: "Quand la fenêtre se cache, les notes restées vides disparaissent.")
            } header: {
                Text("Fenêtre")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Apparence

/// Pastille d'un thème de couleur : fond de nuit + accent, anneau si choisi.
private struct ColorThemeSwatch: View {
    let theme: ColorTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Self.color(theme.night.window))
                Circle().fill(Self.color(theme.night.accent)).padding(5)
            }
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(isSelected ? Color.primary : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1).padding(-2))
        }
        .buttonStyle(.plain)
        .help(theme.label)
        .accessibilityLabel(theme.label)
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct AppearanceSettingsView: View {
    @AppStorage(AppDelegate.themeKey) private var theme = "system"
    @AppStorage(ColorTheme.storageKey) private var colorTheme = ColorTheme.or.rawValue
    @AppStorage("fontSize") private var fontSize: Double = 14
    @AppStorage("listCheckTrigger") private var listCheckTrigger = "/x"
    @AppStorage("listModeShortcutKey") private var listModeShortcutKey = "l"
    @AppStorage("listModeShortcutModifiers") private var listModeShortcutModifiers = "commandShift"

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Picker("Thème", selection: $theme) {
                        Text("Système").tag("system")
                        Text("Clair").tag("light")
                        Text("Sombre").tag("dark")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                } label: {
                    FieldLabel("Thème", help: "Jour, nuit, ou selon le réglage du Mac.")
                }

                LabeledContent {
                    HStack(spacing: 8) {
                        ForEach(ColorTheme.allCases) { option in
                            ColorThemeSwatch(theme: option, isSelected: option.rawValue == colorTheme) {
                                colorTheme = option.rawValue
                            }
                        }
                        Text(ColorTheme(rawValue: colorTheme)?.label ?? ColorTheme.or.label)
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                    }
                } label: {
                    FieldLabel("Couleurs", help: "Accent (contours, cases, curseur) et teinte des fonds assortie. L'icône du Dock suit.")
                }

                LabeledContent {
                    HStack {
                        Slider(value: $fontSize, in: 10...24, step: 1).frame(width: 180)
                        Text("\(Int(fontSize)) pt")
                            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    }
                } label: {
                    FieldLabel("Taille du texte", help: "Taille de base de l'éditeur.")
                }
            } header: {
                Text("Éditeur")
            }

            Section {
                HelpTextField("Déclencheur « coché »", text: $listCheckTrigger,
                              help: "Suffixe ajouté à une ligne cochée (par défaut /x). Cliquer la case le gère pour vous.")

                LabeledContent {
                    HStack {
                        Picker("Modificateurs", selection: $listModeShortcutModifiers) {
                            Text("⌘⇧").tag("commandShift")
                            Text("⌘⌥").tag("commandOption")
                            Text("⌘⌃").tag("commandControl")
                            Text("⌘").tag("command")
                        }
                        .labelsHidden()
                        .frame(width: 90)

                        TextField("Touche", text: $listModeShortcutKey)
                            .labelsHidden()
                            .frame(width: 40)
                            .multilineTextAlignment(.center)
                            .onChange(of: listModeShortcutKey) {
                                let filtered = listModeShortcutKey.lowercased().filter { $0.isLetter || $0.isNumber }
                                listModeShortcutKey = String(filtered.prefix(1))
                                if listModeShortcutKey.isEmpty { listModeShortcutKey = "l" }
                            }
                    }
                } label: {
                    FieldLabel("Raccourci « Convertir en liste »", help: "Transforme la note active en liste cochable.")
                }
            } header: {
                Text("Listes")
            } footer: {
                HelpNote("Les modes se changent aussi avec ⌥⌘1 à ⌥⌘5, ou en tapant math, list, code ou timer en première ligne.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Synchronisation

struct SyncSettingsView: View {
    @ObservedObject private var syncEngine = SyncEngine.shared

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
                HelpToggle("Synchroniser via Nextcloud", isOn: $syncEnabled,
                           help: "WebDAV : un fichier JSON par note dans AlphaNote/notes.")
                    .onChange(of: syncEnabled) {
                        SyncEngine.shared.configureTimer()
                        if syncEnabled { SyncEngine.shared.runManualSync() }
                    }

                HelpTextField("Serveur", text: $nextcloudServerURL, prompt: "https://cloud.exemple.be",
                              help: "Adresse de votre instance Nextcloud.")
                HelpTextField("Utilisateur", text: $nextcloudUsername, help: "Identifiant Nextcloud.")

                LabeledContent {
                    SecureField("Mot de passe d'application", text: $appPassword)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                } label: {
                    FieldLabel("Mot de passe d'application", help: "Créé dans Nextcloud › Sécurité. Stocké dans le trousseau macOS.")
                }

                LabeledContent {
                    Stepper("\(syncIntervalMinutes) min", value: $syncIntervalMinutes, in: 1...60)
                        .onChange(of: syncIntervalMinutes) { SyncEngine.shared.configureTimer() }
                } label: {
                    FieldLabel("Intervalle", help: "Fréquence de la synchronisation automatique. Une modification locale déclenche aussi une sync après 30 s.")
                }

                HStack {
                    Button(isTestingConnection ? "Test…" : "Tester la connexion") {
                        Task { await testConnection() }
                    }
                    .disabled(isTestingConnection)

                    Button("Synchroniser maintenant") {
                        Task { await triggerManualSync() }
                    }
                    .disabled(!syncEnabled)

                    Spacer()
                }

                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(statusColor)
            } header: {
                Text("Nextcloud")
            }

            Section {
                HelpTextField("Dossier Nextcloud Notes", text: $nextcloudNotesFolder,
                              help: "Dossier distant contenant des .md ou .txt (app Notes de Nextcloud).")

                HStack {
                    Button(isImportingNextcloudNotes ? "Import…" : "Importer depuis Nextcloud Notes") {
                        Task { await importNextcloudNotes() }
                    }
                    .disabled(isImportingNextcloudNotes || isImportingAppleNotes)

                    Button(isImportingAppleNotes ? "Import…" : "Importer depuis Apple Notes") {
                        Task { await importAppleNotes() }
                    }
                    .disabled(isImportingAppleNotes || isImportingNextcloudNotes)
                }
            } header: {
                Text("Import")
            } footer: {
                HelpNote("Les doublons (même titre et même contenu) sont ignorés.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadStoredPassword()
            syncIntervalMinutes = max(syncIntervalMinutes, 1)
        }
    }

    private var statusLine: String {
        if let feedbackMessage { return feedbackMessage }
        switch syncEngine.status {
        case .idle: return "État : inactif"
        case .syncing: return "État : synchronisation…"
        case let .success(date): return "Dernière sync : \(date.formatted(date: .abbreviated, time: .shortened))"
        case let .error(message): return "Erreur : \(message)"
        }
    }

    private var statusColor: Color {
        if feedbackMessage != nil { return feedbackIsError ? .red : .green }
        if case .error = syncEngine.status { return .red }
        return .secondary
    }

    @MainActor
    private func loadStoredPassword() {
        do {
            appPassword = try KeychainService.shared.readPassword(serverURL: nextcloudServerURL, username: nextcloudUsername) ?? ""
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }

    @MainActor
    private func persistPasswordIfPossible() throws {
        let server = nextcloudServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = nextcloudUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, !username.isEmpty, !appPassword.isEmpty else { return }
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
            feedbackMessage = "Connexion réussie."
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
            let password = try resolvePassword()
            let report = try await NoteImportService.shared.importNextcloudNotes(
                serverURL: nextcloudServerURL, username: nextcloudUsername,
                password: password, folderPath: nextcloudNotesFolder
            )
            feedbackMessage = report.summary
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
            feedbackMessage = report.scanned == 0
                ? "\(report.summary) Ouvrez Apple Notes une fois, laissez-le se synchroniser, puis réessayez."
                : report.summary
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }

    @MainActor
    private func resolvePassword() throws -> String {
        let inline = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inline.isEmpty { return inline }
        let stored = try KeychainService.shared.readPassword(
            serverURL: nextcloudServerURL.trimmingCharacters(in: .whitespacesAndNewlines),
            username: nextcloudUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard let stored, !stored.isEmpty else { throw SyncConfigurationError.missingPassword }
        return stored
    }
}

// MARK: - Avancé

struct AdvancedSettingsView: View {
    @AppStorage(DatabaseManager.databaseLocationUserDefaultsKey)
    private var databaseLocation = DatabaseManager.defaultDatabaseDirectoryPath()
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var showRelaunchAlert = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(DatabaseManager.resolveDatabaseDirectoryPath(databaseLocation))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                } label: {
                    FieldLabel("Dossier", help: "Dossier contenant alphanote.sqlite.")
                }

                HStack {
                    Button("Déplacer la base…") { chooseDatabaseFolder() }
                    Button("Afficher dans le Finder") {
                        NSWorkspace.shared.selectFile(
                            DatabaseManager.shared.databaseFileURL.path,
                            inFileViewerRootedAtPath: DatabaseManager.resolveDatabaseDirectoryPath(databaseLocation)
                        )
                    }
                    Spacer()
                }

                if let setupError = DatabaseManager.shared.setupErrorMessage {
                    Label(setupError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Base de données")
            } footer: {
                HelpNote("Le déplacement copie la base au nouvel emplacement puis relance AlphaNote. L'ancien fichier n'est pas supprimé.")
            }

            Section {
                HStack {
                    Button("Exporter en JSON…") { exportJSON() }
                    Button("Exporter en Markdown…") { exportMarkdown() }
                    Spacer()
                }
                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.callout)
                        .foregroundStyle(feedbackIsError ? .red : .green)
                }
            } header: {
                Text("Export")
            } footer: {
                HelpNote("JSON : toutes les notes actives avec leurs métadonnées. Markdown : un fichier .md par note dans un dossier.")
            }
        }
        .formStyle(.grouped)
        .alert("Base déplacée", isPresented: $showRelaunchAlert) {
            Button("Relancer AlphaNote") { relaunch() }
        } message: {
            Text("AlphaNote doit redémarrer pour utiliser le nouvel emplacement.")
        }
    }

    private func chooseDatabaseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Choisissez le dossier qui contiendra alphanote.sqlite."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try DatabaseManager.shared.relocateDatabase(to: url)
                feedbackMessage = nil
                showRelaunchAlert = true
            } catch {
                feedbackMessage = error.localizedDescription
                feedbackIsError = true
            }
        }
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        if url.pathExtension == "app" {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", url.path]
            try? task.run()
        }
        NSApp.terminate(nil)
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AlphaNote-export.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(Note.fetchAll()).write(to: url)
                feedbackMessage = "Export JSON terminé."
                feedbackIsError = false
            } catch {
                feedbackMessage = error.localizedDescription
                feedbackIsError = true
            }
        }
    }

    private func exportMarkdown() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Exporter ici"
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            var written = 0
            var usedNames = Set<String>()
            for note in Note.fetchAll() {
                var base = note.effectiveTitle.isEmpty ? "Note \(note.id ?? 0)" : note.effectiveTitle
                base = base.replacingOccurrences(of: #"[/:\\]"#, with: "-", options: .regularExpression)
                base = String(base.prefix(60))
                var name = base
                var counter = 2
                while usedNames.contains(name.lowercased()) {
                    name = "\(base) \(counter)"
                    counter += 1
                }
                usedNames.insert(name.lowercased())
                let fileURL = folder.appendingPathComponent("\(name).md")
                if (try? note.content.write(to: fileURL, atomically: true, encoding: .utf8)) != nil {
                    written += 1
                }
            }
            feedbackMessage = "\(written) note\(written > 1 ? "s" : "") exportée\(written > 1 ? "s" : "") en Markdown."
            feedbackIsError = false
        }
    }
}

// MARK: - Mises à jour

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
                    FieldLabel("Version", help: "Version d'AlphaNote installée.")
                }

                HelpTextField("Appcast", text: $appcastURL, prompt: "https://…/appcast.json",
                              help: "Adresse JSON décrivant la dernière version. Vide = pas de canal configuré.")

                HStack {
                    Button(updater.phase == .checking ? "Vérification…" : "Rechercher des mises à jour") {
                        updater.check(userInitiated: true)
                    }
                    .disabled(updater.phase == .checking || appcastURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }

                HelpNote("AlphaNote vérifie, télécharge, contrôle l'identité du paquet, se remplace puis se relance. Rien n'est installé sans correspondance d'identité.")
            } header: {
                Text("Canal de mise à jour")
            }

            if let feedError = updater.feedConfigurationError {
                Section {
                    Label(feedError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $updater.showingSheet) {
            UpdateSheet(updater: updater)
        }
    }
}
