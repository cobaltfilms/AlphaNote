import SwiftUI
import AppKit

@main
struct AlphaNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var windowController: NoteWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DatabaseManager.shared.setup()
        _ = NSApp.setActivationPolicy(.accessory)

        windowController = NoteWindowController()
        windowController?.showWindow()

        hotkeyManager = HotkeyManager()
        hotkeyManager?.registerGlobalHotkey(keyCode: 0, modifiers: .option) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleWindow()
            }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "AlphaNote") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "AN"
            }
        }
        item.menu = makeStatusMenu()
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregisterAll()
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Open / Hide AlphaNote",
            action: #selector(toggleFromMenu),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

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

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func toggleWindow() {
        guard let windowController else { return }

        if windowController.window?.isVisible == true {
            windowController.hideWindow()
        } else {
            NSApp.unhide(nil)
            windowController.showWindow()
        }
    }
}
