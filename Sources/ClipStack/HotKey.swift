import AppKit
import Carbon
import ClipStackCore

/// A system-wide shortcut via Carbon's RegisterEventHotKey.
/// This needs no special permission and doesn't see any other keystrokes.
final class HotKey {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            me.onPress?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Returns false if the shortcut couldn't be registered (usually: another app already owns it).
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x434C_5053), id: 1) // "CLPS"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}

extension Shortcut {
    init(event: NSEvent) {
        let flags = event.modifierFlags
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= Shortcut.command }
        if flags.contains(.shift) { mods |= Shortcut.shift }
        if flags.contains(.option) { mods |= Shortcut.option }
        if flags.contains(.control) { mods |= Shortcut.control }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods)
    }
}
