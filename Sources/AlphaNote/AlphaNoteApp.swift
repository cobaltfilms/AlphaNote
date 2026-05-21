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
                Button("Nouvelle note") {
                    NotificationCenter.default.post(name: .alphaNoteCreateNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Button("Afficher / Masquer la liste") {
                    NotificationCenter.default.post(name: .alphaNoteToggleSidebar, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Button("Convertir en liste") {
                    NotificationCenter.default.post(name: .alphaNoteConvertToList, object: nil)
                }
                .keyboardShortcut(listModeShortcutKeyEquivalent, modifiers: listModeShortcutModifierFlags)
            }

            CommandGroup(replacing: .help) {
                Button("AlphaNote Help") {
                    NotificationCenter.default.post(name: .alphaNoteOpenHelpCenter, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
    }

    private var listModeShortcutKeyEquivalent: KeyEquivalent {
        let lower = listModeShortcutKey.lowercased()
        let first = lower.first ?? "l"
        return KeyEquivalent(first)
    }

    private var listModeShortcutModifierFlags: EventModifiers {
        switch listModeShortcutModifiers {
        case "command":
            return [.command]
        case "commandOption":
            return [.command, .option]
        case "commandControl":
            return [.command, .control]
        case "commandShift":
            fallthrough
        default:
            return [.command, .shift]
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var windowController: NoteWindowController?
    private var settingsWindowController: NSWindowController?
    private var helpWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var savedNoteWindowLevel: NSWindow.Level?
    private var observedSettingsWindows = Set<ObjectIdentifier>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        DatabaseManager.shared.setup()
        SyncEngine.shared.start()
        _ = NSApp.setActivationPolicy(.regular)
        configureDockIcon()

        windowController = NoteWindowController()
        windowController?.showWindow()

        hotkeyManager = HotkeyManager()
        hotkeyManager?.registerGlobalHotkey(keyCode: 0, modifiers: .option) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleWindow()
            }
        }

        configureStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openHelpCenter),
            name: .alphaNoteOpenHelpCenter,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregisterAll()
    }

    private func configureDockIcon() {
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size)

        image.lockFocus()

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let bgRect = NSRect(x: 96, y: 96, width: 832, height: 832)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 180, yRadius: 180)

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.set()

        NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1).setFill()
        bgPath.fill()

        NSGraphicsContext.current?.restoreGraphicsState()

        let font = NSFont(name: "Menlo-Bold", size: 560) ?? NSFont.systemFont(ofSize: 560, weight: .bold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1)
        ]
        NSString(string: "A").draw(at: NSPoint(x: 305, y: 245), withAttributes: textAttributes)

        NSColor(calibratedRed: 1.0, green: 0.73, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 596, y: 298, width: 36, height: 405), xRadius: 10, yRadius: 10).fill()

        image.unlockFocus()

        NSApp.applicationIconImage = image
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = nil
            button.title = "A|"
            button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
            button.toolTip = "AlphaNote"
        }
        item.menu = makeStatusMenu()
        statusItem = item
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "AlphaNote", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: "Toggle Window",
            action: #selector(toggleFromMenu),
            keyEquivalent: "a"
        )
        toggleItem.keyEquivalentModifierMask = [.option]
        toggleItem.target = self
        menu.addItem(toggleItem)

        let newNoteItem = NSMenuItem(
            title: "New Note",
            action: #selector(createNoteFromMenu),
            keyEquivalent: "n"
        )
        newNoteItem.keyEquivalentModifierMask = [.option]
        newNoteItem.target = self
        menu.addItem(newNoteItem)

        let toggleListItem = NSMenuItem(
            title: "Toggle Note List",
            action: #selector(toggleListFromMenu),
            keyEquivalent: "l"
        )
        toggleListItem.keyEquivalentModifierMask = [.option]
        toggleListItem.target = self
        menu.addItem(toggleListItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let helpItem = NSMenuItem(
            title: "Centre d’aide",
            action: #selector(openHelpCenterFromMenu),
            keyEquivalent: "h"
        )
        helpItem.keyEquivalentModifierMask = [.command, .shift]
        helpItem.target = self
        menu.addItem(helpItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit AlphaNote",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func toggleFromMenu() {
        toggleWindow()
    }

    @objc private func createNoteFromMenu() {
        showWindowIfNeeded()
        NotificationCenter.default.post(name: .alphaNoteCreateNote, object: nil)
    }

    @objc private func toggleListFromMenu() {
        showWindowIfNeeded()
        NotificationCenter.default.post(name: .alphaNoteToggleSidebar, object: nil)
    }

    @objc private func openSettings() {
        demoteNoteWindowForSettings()
        // Always use an AppKit settings window to avoid SwiftUI Settings scene invalidation edge cases.
        showFallbackSettingsWindow()
        _ = bringSettingsToFront()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            let found = self.bringSettingsToFront()
            if !found {
                self.restoreNoteWindowLevelIfNeeded()
            }
        }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHelpCenterFromMenu() {
        openHelpCenter()
    }

    @objc private func openHelpCenter() {
        if let existingWindow = helpWindowController?.window {
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let helpView = HelpCenterView()
        let hostingView = NSHostingView(rootView: helpView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Aide AlphaNote"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = hostingView

        let controller = NSWindowController(window: window)
        helpWindowController = controller
        controller.showWindow(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showWindowIfNeeded() {
        ensureMainWindowController()
        guard let windowController else { return }
        NSApp.unhide(nil)
        windowController.showWindow()
    }

    private func showFallbackSettingsWindow() {
        if let existingWindow = settingsWindowController?.window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 390),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.level = .modalPanel
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = hostingView

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        attachSettingsCloseHandler(to: window)
        controller.showWindow(nil)
    }

    @discardableResult
    private func bringSettingsToFront() -> Bool {
        let settingsWindows = NSApp.windows.filter { [weak self] window in
            if window === self?.settingsWindowController?.window {
                return true
            }

            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let settingsLikeTitle =
                title.contains("settings") ||
                title.contains("preferences") ||
                title.contains("réglages")

            return settingsLikeTitle
        }

        guard !settingsWindows.isEmpty else { return false }

        for window in settingsWindows {
            window.level = .modalPanel
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            attachSettingsCloseHandler(to: window)
        }
        return true
    }

    private func demoteNoteWindowForSettings() {
        guard let noteWindow = windowController?.window else { return }
        if savedNoteWindowLevel == nil {
            savedNoteWindowLevel = noteWindow.level
        }
        noteWindow.level = .normal
    }

    private func restoreNoteWindowLevelIfNeeded() {
        guard let noteWindow = windowController?.window,
              let previousLevel = savedNoteWindowLevel else {
            return
        }

        noteWindow.level = previousLevel
        savedNoteWindowLevel = nil
    }

    private func attachSettingsCloseHandler(to window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard !observedSettingsWindows.contains(id) else { return }
        observedSettingsWindows.insert(id)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let closingWindow = notification.object as? NSWindow {
                self.observedSettingsWindows.remove(ObjectIdentifier(closingWindow))
            }
            self.restoreNoteWindowLevelIfNeeded()
        }
    }

    private func toggleWindow() {
        ensureMainWindowController()
        guard let windowController else { return }

        if windowController.window?.isVisible == true {
            windowController.hideWindow()
        } else {
            NSApp.unhide(nil)
            windowController.showWindow()
        }
    }

    private func ensureMainWindowController() {
        if windowController == nil {
            windowController = NoteWindowController()
        }
    }
}
