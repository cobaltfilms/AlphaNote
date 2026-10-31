import SwiftUI
import AppKit

@main
struct AlphaNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("listModeShortcutKey") private var listModeShortcutKey: String = "l"
    @AppStorage("listModeShortcutModifiers") private var listModeShortcutModifiers: String = "commandShift"

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandMenu("Notes") {
                Button("Nouvelle note") { post(.alphaNoteCreateNote) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Note précédente") { post(.alphaNoteNavigatePrevious) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("Note suivante") { post(.alphaNoteNavigateNext) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

                Divider()

                Button("Afficher / masquer la liste") { post(.alphaNoteToggleSidebar) }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Button("Demande en langage naturel…") { post(.alphaNoteToggleCommandField) }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("Rechercher dans les notes…") { post(.alphaNoteFocusSearch) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Menu("Mode") {
                    ForEach(NoteMode.allCases, id: \.self) { mode in
                        Button(mode.title) {
                            NotificationCenter.default.post(name: .alphaNoteSetMode, object: mode)
                        }
                        .keyboardShortcut(mode.shortcutKey, modifiers: [.command, .option])
                    }
                }
                Button("Convertir en liste") { post(.alphaNoteConvertToList) }
                    .keyboardShortcut(listModeShortcutKeyEquivalent, modifiers: listModeShortcutModifierFlags)

                Divider()

                Button("Épingler / désépingler") { post(.alphaNoteTogglePin) }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button("Archiver la note") { post(.alphaNoteArchiveCurrent) }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Button("Supprimer la note") { post(.alphaNoteDeleteCurrent) }
                    .keyboardShortcut(.delete, modifiers: [.command, .option])
            }

            CommandGroup(replacing: .help) {
                Button("Aide AlphaNote") { post(.alphaNoteOpenHelpCenter) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }

            CommandGroup(after: .appInfo) {
                Button("Rechercher des mises à jour…") { post(.alphaNoteCheckForUpdates) }
            }
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    private var listModeShortcutKeyEquivalent: KeyEquivalent {
        KeyEquivalent(listModeShortcutKey.lowercased().first ?? "l")
    }

    private var listModeShortcutModifierFlags: EventModifiers {
        switch listModeShortcutModifiers {
        case "command": return [.command]
        case "commandOption": return [.command, .option]
        case "commandControl": return [.command, .control]
        default: return [.command, .shift]
        }
    }
}

extension NoteMode {
    var title: String {
        switch self {
        case .plain: return "Texte"
        case .math: return "Math"
        case .list: return "Liste"
        case .code: return "Code"
        case .timer: return "Minuteur"
        }
    }

    var symbol: String {
        switch self {
        case .plain: return "text.alignleft"
        case .math: return "function"
        case .list: return "checklist"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .timer: return "timer"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .plain: return "1"
        case .math: return "2"
        case .list: return "3"
        case .code: return "4"
        case .timer: return "5"
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let showInDockKey = "showInDock"
    static let showInMenuBarKey = "showInMenuBar"
    static let autoCleanupKey = "autoCleanup"
    static let themeKey = "theme"

    private var hotkeyManager = HotkeyManager()
    private var windowController: NoteWindowController?
    private var helpWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var appliedHotkey: (UInt32, UInt)?
    private var observers: [NSObjectProtocol] = []

    static let defaultAppcastURL = "https://raw.githubusercontent.com/cobaltfilms/AlphaNote/main/appcast.json"
    private static let legacyAppcastURL = "https://git.cobaltfilms.be/paul/AlphaNote/raw/branch/main/appcast.json"

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            HotkeySettings.enabledKey: true,
            Self.showInDockKey: true,
            Self.showInMenuBarKey: true,
            Self.autoCleanupKey: true,
            NoteWindowController.alwaysOnTopKey: true,
            Self.themeKey: "system",
            "fontSize": 14.0,
            "listCheckTrigger": "/x",
            // Canal de mise à jour par défaut : l'appcast du dépôt public de releases
            // (Gitea exige une connexion, même pour un dépôt public).
            AISettingsKeys.updateAppcastURL: Self.defaultAppcastURL
        ])
        if UserDefaults.standard.string(forKey: AISettingsKeys.updateAppcastURL) == Self.legacyAppcastURL {
            UserDefaults.standard.removeObject(forKey: AISettingsKeys.updateAppcastURL)
        }

        PreferencesMigration.migrateLegacyDefaultsIfNeeded()
        DatabaseManager.shared.setup()
        SyncEngine.shared.start()
        if UserDefaults.standard.bool(forKey: LANSyncServer.enabledKey) { LANSyncServer.shared.start() }
        applyTheme()
        applyActivationPolicy()
        applyColorTheme()

        windowController = NoteWindowController()
        windowController?.showWindow()

        hotkeyManager.onHotkey = { [weak self] in self?.windowController?.toggle() }
        applyHotkey()
        applyStatusItem()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .alphaNoteOpenHelpCenter, object: nil, queue: .main) { [weak self] _ in self?.openHelpCenter() },
            center.addObserver(forName: .alphaNoteCheckForUpdates, object: nil, queue: .main) { [weak self] _ in self?.checkForUpdates() },
            center.addObserver(forName: .alphaNoteHideWindow, object: nil, queue: .main) { [weak self] _ in self?.windowController?.hideWindow() },
            center.addObserver(forName: .alphaNoteOpenSettings, object: nil, queue: .main) { [weak self] _ in self?.openSettings() },
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.applySettings() },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                self?.windowDidBecomeKey(note.object as? NSWindow)
            }
        ]

        Task { @MainActor in
            UpdateManager.shared.checkOnLaunch()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .alphaNoteWindowWillHide, object: nil)
        hotkeyManager.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.showWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: Réglages appliqués à chaud

    private func applySettings() {
        applyHotkey()
        applyStatusItem()
        applyActivationPolicy()
        applyTheme()
        applyColorTheme()
        windowController?.applyLevel()
        windowController?.applyMinimumWidth()
    }

    private var appliedColorTheme: ColorTheme?

    /// Thème de couleur : fond de la fenêtre (AppKit) et icône du Dock. Les
    /// vues SwiftUI se reconstruisent d'elles-mêmes (NoteListView).
    private func applyColorTheme() {
        let theme = ColorTheme.current
        guard theme != appliedColorTheme else { return }
        appliedColorTheme = theme
        windowController?.window?.backgroundColor = Palette.window
        NSApp.applicationIconImage = AppIconRenderer.image(accent: theme.night.accent)
    }

    private func applyHotkey() {
        guard HotkeySettings.isEnabled else {
            hotkeyManager.unregister()
            appliedHotkey = nil
            return
        }
        let keyCode = HotkeySettings.keyCode
        let modifiers = HotkeySettings.modifiers
        if let applied = appliedHotkey, applied.0 == keyCode, applied.1 == modifiers.rawValue { return }
        if hotkeyManager.register(keyCode: keyCode, modifiers: modifiers) {
            appliedHotkey = (keyCode, modifiers.rawValue)
        } else {
            appliedHotkey = nil
        }
    }

    private func applyActivationPolicy() {
        let showInDock = UserDefaults.standard.bool(forKey: Self.showInDockKey)
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private func applyStatusItem() {
        let showInMenuBar = UserDefaults.standard.bool(forKey: Self.showInMenuBarKey)
            || !UserDefaults.standard.bool(forKey: Self.showInDockKey) // jamais les deux absents
        if showInMenuBar, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "AlphaNote")
                image?.isTemplate = true
                button.image = image
                button.toolTip = "AlphaNote (\(HotkeySettings.displayString))"
            }
            item.menu = makeStatusMenu()
            statusItem = item
        } else if !showInMenuBar, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        } else if let button = statusItem?.button {
            button.toolTip = "AlphaNote (\(HotkeySettings.displayString))"
        }
    }

    private func applyTheme() {
        let wanted: NSAppearance.Name?
        switch UserDefaults.standard.string(forKey: Self.themeKey) ?? "system" {
        case "light": wanted = .aqua
        case "dark": wanted = .darkAqua
        default: wanted = nil
        }
        guard NSApp.appearance?.name != wanted else { return }
        NSApp.appearance = wanted.map { NSAppearance(named: $0) } ?? nil
    }

    /// La fenêtre de notes flotte au-dessus de tout — sauf quand une autre
    /// fenêtre d'AlphaNote (Réglages, Aide) passe devant.
    private func windowDidBecomeKey(_ window: NSWindow?) {
        guard let window, let noteWindow = windowController?.window else { return }
        if window === noteWindow {
            windowController?.applyLevel()
        } else {
            windowController?.demote()
        }
    }

    // MARK: Menu de la barre des menus

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Afficher / masquer AlphaNote", action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let newNoteItem = NSMenuItem(title: "Nouvelle note", action: #selector(createNoteFromMenu), keyEquivalent: "n")
        newNoteItem.keyEquivalentModifierMask = [.command, .option]
        newNoteItem.target = self
        menu.addItem(newNoteItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let helpItem = NSMenuItem(title: "Aide AlphaNote", action: #selector(openHelpCenter), keyEquivalent: "h")
        helpItem.keyEquivalentModifierMask = [.command, .shift]
        helpItem.target = self
        menu.addItem(helpItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quitter AlphaNote", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func toggleFromMenu() {
        windowController?.toggle()
    }

    @objc private func createNoteFromMenu() {
        windowController?.showWindow()
        NotificationCenter.default.post(name: .alphaNoteCreateNote, object: nil)
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Fenêtre Réglages SwiftUI (scène `Settings`) — un seul chemin d'ouverture.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func checkForUpdates() {
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                UpdateManager.shared.check(userInitiated: true)
            }
        }
    }

    @objc private func openHelpCenter() {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = helpWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Aide AlphaNote"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: HelpCenterView())

        let controller = NSWindowController(window: window)
        helpWindowController = controller
        controller.showWindow(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
