import AppKit
import SwiftUI

extension Notification.Name {
    static let alphaNoteWindowWillHide = Notification.Name("alphaNoteWindowWillHide")
    static let alphaNoteWindowDidShow = Notification.Name("alphaNoteWindowDidShow")
    static let alphaNoteHideWindow = Notification.Name("alphaNoteHideWindow")
}

private final class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// La fenêtre-bloc-notes : flottante (réglage « toujours au premier plan »),
/// cadre mémorisé, suit l'espace actif, se cache avec Échap ou le raccourci.
final class NoteWindowController: NSWindowController, NSWindowDelegate {
    static let alwaysOnTopKey = "alwaysOnTop"
    static let sidebarVisibleKey = "sidebarVisible"

    /// Volet des notes (260) + zone de note assez large pour le minuteur.
    private static let sidebarWidth: CGFloat = 260
    private static let minimumNoteWidth: CGFloat = 400
    private static let defaultWidth: CGFloat = 680
    private var hostingView: NSHostingView<NoteListView>!
    private var isHiding = false

    init() {
        let window = NoteWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.defaultWidth, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.window
        window.isOpaque = true // rien ne doit transparaître des fenêtres du dessous
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setFrameAutosaveName("AlphaNoteMainWindow")
        if !window.setFrameUsingName("AlphaNoteMainWindow") {
            window.center()
        }

        hostingView = NSHostingView(rootView: NoteListView())
        // La vue SwiftUI ne pilote jamais la taille de la fenêtre : ouvrir le
        // volet des notes ne doit pas élargir la fenêtre, il partage la place.
        hostingView.sizingOptions = []
        window.contentView = hostingView

        super.init(window: window)
        window.delegate = self
        applyLevel()
        applyMinimumWidth()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool { window?.isVisible == true }

    func applyLevel() {
        guard let window else { return }
        let onTop = UserDefaults.standard.object(forKey: Self.alwaysOnTopKey) as? Bool ?? true
        window.level = onTop ? .floating : .normal
    }

    /// Largeur minimale selon le volet des notes : ouvert, la fenêtre s'élargit
    /// juste assez pour que la note garde sa place (sinon tout est rogné).
    func applyMinimumWidth() {
        guard let window else { return }
        let sidebarVisible = UserDefaults.standard.bool(forKey: Self.sidebarVisibleKey)
        let minimum = Self.minimumNoteWidth + (sidebarVisible ? Self.sidebarWidth + 1 : 0)
        window.contentMinSize = NSSize(width: minimum, height: 320)
        let content = window.contentRect(forFrameRect: window.frame)
        guard content.width < minimum else { return }
        var frame = window.frame
        frame.size.width += minimum - content.width
        if let screen = window.screen?.visibleFrame, frame.maxX > screen.maxX {
            frame.origin.x = max(screen.minX, screen.maxX - frame.width)
        }
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    /// Passe temporairement au niveau normal (quand Réglages ou l'Aide est au
    /// premier plan) pour ne pas les recouvrir.
    func demote() {
        window?.level = .normal
    }

    func showWindow() {
        guard let window else { return }
        applyLevel()
        window.backgroundColor = Palette.window

        NSApp.activate(ignoringOtherApps: true)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.makeMain()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }

        DispatchQueue.main.async { [weak self] in
            self?.focusEditor()
            NotificationCenter.default.post(name: .alphaNoteWindowDidShow, object: nil)
        }
    }

    func hideWindow() {
        guard let window, window.isVisible, !isHiding else { return }
        isHiding = true
        NotificationCenter.default.post(name: .alphaNoteWindowWillHide, object: nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            window.orderOut(nil)
            window.alphaValue = 1
            self?.isHiding = false
        }
    }

    func toggle() {
        if isVisible, window?.isKeyWindow == true {
            hideWindow()
        } else if isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            focusEditor()
        } else {
            showWindow()
        }
    }

    func focusEditor() {
        guard let window, let contentView = window.contentView,
              let textView = firstTextView(in: contentView) else { return }
        window.makeFirstResponder(textView)
    }

    private func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NoteTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow()
        return false
    }
}
