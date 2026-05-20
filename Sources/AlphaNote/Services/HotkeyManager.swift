import Cocoa
import Carbon

final class HotkeyManager {
    private var globalHotkeyRef: EventHotKeyRef?
    private var localMonitor: Any?
    var hotkeyCallback: (() -> Void)?

    // Carbon hotkey signature
    private static let hotkeySignature: FourCharCode = {
        let chars: [UInt8] = [0x41, 0x4C, 0x50, 0x4E] // "ALPN"
        return FourCharCode(chars[0]) << 24 | FourCharCode(chars[1]) << 16 | FourCharCode(chars[2]) << 8 | FourCharCode(chars[3])
    }()

    func registerGlobalHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, callback: @escaping () -> Void) {
        hotkeyCallback = callback

        // Carbon global hotkey
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        var hotKeyID = EventHotKeyID(signature: Self.hotkeySignature, id: 1)

        let carbonMods = carbonModifiers(from: modifiers)
        RegisterEventHotKey(keyCode, carbonMods, hotKeyID, GetApplicationEventTarget(), 0, &globalHotkeyRef)

        // Local monitor for when app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matchesHotkey(event, keyCode: keyCode, modifiers: modifiers) else {
                return event
            }
            self.hotkeyCallback?()
            return nil
        }
    }

    func unregisterAll() {
        if let ref = globalHotkeyRef {
            UnregisterEventHotKey(ref)
            globalHotkeyRef = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        hotkeyCallback = nil
    }

    // MARK: - Convenience

    func register() {
        // Option+A = keyCode 0
        registerGlobalHotkey(keyCode: 0, modifiers: .option) { [weak self] in
            self?.hotkeyCallback?()
        }
    }

    func unregister() {
        unregisterAll()
    }

    // MARK: - Private Helpers

    private func matchesHotkey(_ event: NSEvent, keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        return event.keyCode == keyCode && event.modifierFlags.contains(modifiers)
    }

    private func carbonModifiers(from nsModifiers: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if nsModifiers.contains(.option) { mods |= UInt32(optionKey) }
        if nsModifiers.contains(.control) { mods |= UInt32(controlKey) }
        if nsModifiers.contains(.shift) { mods |= UInt32(shiftKey) }
        if nsModifiers.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }
}

// MARK: - Carbon Event Handler

private func hotkeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData,
          let event else { return OSStatus(eventNotHandledErr) }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else { return status }
    manager.hotkeyCallback?()

    return noErr
}