import Cocoa
import Carbon

/// Raccourci global (Carbon `RegisterEventHotKey`), reconfigurable à chaud.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var currentKeyCode: UInt32?
    private(set) var currentModifiers: NSEvent.ModifierFlags = []
    var onHotkey: (() -> Void)?

    private static let signature: FourCharCode = 0x414C504E // "ALPN"

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Enregistre (ou ré-enregistre) le raccourci. Retourne faux si le système
    /// le refuse (déjà pris par une autre app).
    @discardableResult
    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        unregister()
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            keyCode, Self.carbonModifiers(from: modifiers), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr else {
            hotKeyRef = nil
            return false
        }
        currentKeyCode = keyCode
        currentModifiers = modifiers
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        currentKeyCode = nil
        currentModifiers = []
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }
}

private func hotkeyEventHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { manager.onHotkey?() }
    return noErr
}

// MARK: - Réglage du raccourci

/// Lecture/écriture du raccourci global dans UserDefaults, et texte lisible.
enum HotkeySettings {
    static let enabledKey = "hotkeyEnabled"
    static let keyCodeKey = "hotkeyKeyCode"
    static let modifiersKey = "hotkeyModifiers"

    /// Touche « A » de la disposition clavier courante (0 sur QWERTY, 12 sur AZERTY).
    static var defaultKeyCode: UInt32 { keyCode(forCharacter: "a") ?? 0 }
    static let defaultModifiers: NSEvent.ModifierFlags = [.option]

    /// Cherche le code de touche qui produit `character` avec la disposition
    /// courante — le raccourci est physique (Carbon), l'étiquette doit suivre.
    static func keyCode(forCharacter character: Character) -> UInt32? {
        let wanted = String(character).lowercased()
        for code in UInt32(0)...UInt32(50) where keyName(for: code).lowercased() == wanted {
            return code
        }
        return nil
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var keyCode: UInt32 {
        let raw = UserDefaults.standard.object(forKey: keyCodeKey) as? Int
        return raw.map { UInt32($0) } ?? defaultKeyCode
    }

    static var modifiers: NSEvent.ModifierFlags {
        guard let raw = UserDefaults.standard.object(forKey: modifiersKey) as? UInt else { return defaultModifiers }
        return NSEvent.ModifierFlags(rawValue: raw).intersection([.command, .option, .control, .shift])
    }

    static func save(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        UserDefaults.standard.set(Int(keyCode), forKey: keyCodeKey)
        UserDefaults.standard.set(modifiers.intersection([.command, .option, .control, .shift]).rawValue, forKey: modifiersKey)
    }

    static var displayString: String {
        describe(keyCode: keyCode, modifiers: modifiers)
    }

    static func describe(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyName(for: keyCode)
    }

    static func keyName(for keyCode: UInt32) -> String {
        let special: [UInt32: String] = [
            36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let name = special[keyCode] { return name }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "key \(keyCode)"
        }
        let layoutData = unsafeBitCast(layoutPointer, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(base, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
