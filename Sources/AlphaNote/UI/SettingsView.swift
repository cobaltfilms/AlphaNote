import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            KeywordSettingsView()
                .tabItem {
                    Label("Keywords", systemImage: "tag")
                }

            AISettingsView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 580, height: 440)
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
            Toggle("Enable global hotkey (⌥A)", isOn: $hotkeyEnabled)
            Toggle("Show in Dock", isOn: $showInDock)
            Toggle("Show in Menu Bar", isOn: $showInMenuBar)
            Toggle("Auto-cleanup empty notes", isOn: $autoCleanup)
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
            Picker("Theme", selection: $theme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }

            VStack(alignment: .leading) {
                Text("Font Size: \(Int(fontSize))")
                Slider(value: $fontSize, in: 10...24, step: 1)
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
            TextField("Math keyword", text: $keywordMath)
            TextField("List keyword", text: $keywordList)
            TextField("Code keyword", text: $keywordCode)
            TextField("Timer keyword", text: $keywordTimer)
            TextField("List check trigger", text: $listCheckTrigger)
            HStack {
                Picker("List shortcut", selection: $listModeShortcutModifiers) {
                    Text("⌘⇧").tag("commandShift")
                    Text("⌘⌥").tag("commandOption")
                    Text("⌘⌃").tag("commandControl")
                    Text("⌘").tag("command")
                }
                .frame(width: 140)

                TextField("Key", text: $listModeShortcutKey)
                    .frame(width: 40)
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
                TextField("Database location", text: $databaseLocation)
            } header: {
                Text("Database")
            }

            Section {
                Toggle("Enable cloud sync", isOn: $syncEnabled)
                    .onChange(of: syncEnabled) {
                        SyncEngine.shared.configureTimer()
                        if syncEnabled {
                            SyncEngine.shared.runManualSync()
                        }
                    }

                TextField("Server URL", text: $nextcloudServerURL)

                TextField("Username", text: $nextcloudUsername)

                SecureField("App password", text: $appPassword)

                Stepper("Sync interval: \(syncIntervalMinutes) min", value: $syncIntervalMinutes, in: 1...60)
                    .onChange(of: syncIntervalMinutes) {
                        SyncEngine.shared.configureTimer()
                    }

                HStack {
                    Button(isTestingConnection ? "Testing..." : "Test connection") {
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
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
            } header: {
                Text("Cloud Sync (Nextcloud)")
            }

            Section {
                TextField("Nextcloud Notes folder", text: $nextcloudNotesFolder)

                HStack {
                    Button(isImportingNextcloudNotes ? "Importing Nextcloud Notes..." : "Import Nextcloud Notes") {
                        Task { await importNextcloudNotes() }
                    }
                    .disabled(isImportingNextcloudNotes || isImportingAppleNotes)

                    Button(isImportingAppleNotes ? "Importing Apple Notes..." : "Import Apple Notes") {
                        Task { await importAppleNotes() }
                    }
                    .disabled(isImportingAppleNotes || isImportingNextcloudNotes)
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(feedbackIsError ? .red : .green)
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Imports skip duplicates automatically.")
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
            return "Status: syncing..."
        case let .success(date):
            return "Status: success (\(date.formatted(date: .abbreviated, time: .shortened)))"
        case let .error(message):
            return "Status: error - \(message)"
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
                feedbackMessage = "\(report.summary) If you expected notes, open Apple Notes once, wait for sync to finish, then retry import."
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
