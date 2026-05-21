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
