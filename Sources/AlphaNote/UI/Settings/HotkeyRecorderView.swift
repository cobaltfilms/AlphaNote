import SwiftUI
import AppKit

/// Champ « enregistreur de raccourci » : clic, puis appui sur une combinaison
/// avec au moins un modificateur (ou une touche de fonction).
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: UInt

    func makeNSView(context: Context) -> RecorderControl {
        let control = RecorderControl()
        control.onRecord = { code, flags in
            keyCode = Int(code)
            modifiers = flags.rawValue
        }
        control.display = HotkeySettings.describe(keyCode: UInt32(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
        return control
    }

    func updateNSView(_ control: RecorderControl, context: Context) {
        if !control.isRecording {
            control.display = HotkeySettings.describe(keyCode: UInt32(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
        }
    }

    final class RecorderControl: NSView {
        var onRecord: (UInt32, NSEvent.ModifierFlags) -> Void = { _, _ in }
        var display = "" { didSet { needsDisplay = true } }
        private(set) var isRecording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 26) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            isRecording = true
        }

        override func becomeFirstResponder() -> Bool {
            isRecording = true
            return true
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return true
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else { return false }
            return handle(event)
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { return super.keyDown(with: event) }
            if !handle(event) { NSSound.beep() }
        }

        private func handle(_ event: NSEvent) -> Bool {
            if event.keyCode == 53 { // Échap : annule
                isRecording = false
                window?.makeFirstResponder(nil)
                return true
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isFunctionKey = (96...122).contains(event.keyCode)
            guard !flags.isEmpty || isFunctionKey else { return false }
            onRecord(UInt32(event.keyCode), flags)
            isRecording = false
            window?.makeFirstResponder(nil)
            return true
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
            path.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = isRecording ? 1.5 : 1
            path.stroke()

            let text = isRecording ? "Appuyez sur une combinaison…" : display
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: isRecording ? 11 : 13, weight: .medium),
                .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            (text as NSString).draw(at: origin, withAttributes: attributes)
        }
    }
}
