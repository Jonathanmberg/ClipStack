import AppKit
import ApplicationServices
import Carbon

/// Puts text on the clipboard and presses ⌘V in the app the user was typing in.
///
/// Sending a synthetic ⌘V requires the Accessibility permission. Without it ClipStack still
/// copies the clip, and the user presses ⌘V themselves.
enum Paster {
    static var canAutoPaste: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow Accessibility" prompt (only appears if not yet allowed).
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
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
        if let app, app != NSRunningApplication.current, !app.isActive {
            app.activate(options: [])
        }
        // Give the target app a moment to take focus back from the popup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let v = keyCode(for: "v") ?? 9
            let source = CGEventSource(stateID: .combinedSessionState)
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: isDown)
                event?.flags = .maskCommand
                event?.post(tap: .cgSessionEventTap)
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

/// Where the text cursor is on screen, when the focused app exposes it through Accessibility.
enum Caret {
    static func rect() -> NSRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1) // never let a slow app delay the popup

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }

        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &r), r.height > 0 else { return nil }

        // Accessibility uses top-left screen coordinates; AppKit uses bottom-left.
        guard let primary = NSScreen.screens.first else { return nil }
        let flipped = NSRect(x: r.minX, y: primary.frame.maxY - r.maxY, width: max(r.width, 1), height: r.height)
        // Some apps report (0,0) or off-screen garbage; only trust a rect that's on a screen.
        guard NSScreen.screens.contains(where: { $0.frame.contains(flipped.origin) }),
              !(r.minX == 0 && r.minY == 0) else { return nil }
        return flipped
    }
}
