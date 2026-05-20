import SwiftUI

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

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 450, height: 300)
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

    var body: some View {
        Form {
            TextField("Math keyword", text: $keywordMath)
            TextField("List keyword", text: $keywordList)
            TextField("Code keyword", text: $keywordCode)
            TextField("Timer keyword", text: $keywordTimer)
        }
        .padding(20)
    }
}

// MARK: - Advanced

struct AdvancedSettingsView: View {
    @AppStorage("databaseLocation") private var databaseLocation = "~/Application Support/AlphaNote"

    var body: some View {
        Form {
            TextField("Database location", text: $databaseLocation)
            HStack {
                Spacer()
                Button("Reveal in Finder") {
                    let url = URL(fileURLWithPath: databaseLocation.replacingOccurrences(of: "~", with: NSHomeDirectory()))
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
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
}