import AppKit
import ApplicationServices
import Carbon

/// Puts text on the clipboard and presses ⌘V in the app the user was typing in.
///
/// Sending a synthetic ⌘V requires the Accessibility permission. Without it ClipStack still
/// copies the clip, and the user presses ⌘V themselves.
enum Paster {
    /// Whether macOS lets this exact copy of ClipStack send keystrokes.
    static var canAutoPaste: Bool { CGPreflightPostEventAccess() || AXIsProcessTrusted() }

    /// Shows the system "allow Accessibility" prompt (only appears if not yet allowed).
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        CGRequestPostEventAccess()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func pressPaste(in app: NSRunningApplication?) {
        // The popup held the keyboard; hand focus back explicitly, even if the app still
        // counts as "active", so the ⌘V lands in its text field and not nowhere.
        if let app, app != NSRunningApplication.current {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let v = keyCode(for: "v") ?? 9
            // A private source so modifier keys still physically held (⌃⌥ from the shortcut)
            // don't get mixed into the ⌘V.
            let source = CGEventSource(stateID: .privateState)
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: isDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap) // exactly like a real key press
            }
        }
    }

    /// The key that types `character` in the current keyboard layout, so ⌘V also works on
    /// layouts like Dvorak or AZERTY where "V" isn't on the QWERTY V key.
    private static func keyCode(for character: String) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, chars.count, &length, &chars)
                if status == noErr, length > 0, String(utf16CodeUnits: chars, count: length) == character {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }
}
