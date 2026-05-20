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

class AppDelegate: NSObject, NSApplicationDelegate {
    var hotkeyManager: HotkeyManager!
    var windowController: NoteWindowController!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        DatabaseManager.shared.setup()

        windowController = NoteWindowController()

        hotkeyManager = HotkeyManager(
            key: .a,
            modifiers: .option
        ) { [weak self] in
            self?.toggleWindow()
        }
        hotkeyManager.register()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "AlphaNote")
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.windowController.hideWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
    }

    @objc private func statusItemClicked() {
        toggleWindow()
    }

    private func toggleWindow() {
        if windowController.window?.isVisible == true {
            windowController.hideWindow()
        } else {
            windowController.showWindow()
        }
    }
}