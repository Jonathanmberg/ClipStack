import Foundation

/// A global keyboard shortcut: a virtual key code plus Carbon modifier flags.
public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    // Carbon modifier bits (same values as cmdKey, shiftKey, optionKey, controlKey).
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    /// ⌃⌥V — free in practically every app, unlike ⌘X (Cut) or ⌘⇧V (paste as plain text).
    public static let `default` = Shortcut(keyCode: 9, modifiers: control | option)

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & (Self.command | Self.shift | Self.option | Self.control)
    }

    /// A global shortcut needs ⌘, ⌥ or ⌃, otherwise it would swallow normal typing.
    public var isUsable: Bool {
        modifiers & (Self.command | Self.option | Self.control) != 0
    }

    /// Apple's order: ⌃⌥⇧⌘ then the key, e.g. "⌃⌥V".
    public var displayString: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    public static func keyName(_ code: UInt32) -> String {
        keyNames[code] ?? "Key \(code)"
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K",
        37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
        9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
