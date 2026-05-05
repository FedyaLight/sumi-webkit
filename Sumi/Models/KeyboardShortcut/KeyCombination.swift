import AppKit
import Foundation

struct KeyCombination: Hashable, Codable {
    let key: String
    let modifiers: Modifiers

    init(key: String, modifiers: Modifiers = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    var displayString: String {
        var parts = modifiers.displayStrings
        parts.append(key.uppercased())
        return parts.joined(separator: " + ")
    }

    var lookupKey: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.shift) { parts.append("shift") }
        parts.append(key.lowercased())
        return parts.joined(separator: "+")
    }

    private static let physicalKeyMap: [UInt16: String] = [
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g", 0x06: "z", 0x07: "x",
        0x08: "c", 0x09: "v", 0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y",
        0x11: "t", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "o", 0x20: "u",
        0x21: "[", 0x22: "i", 0x23: "p", 0x24: "return", 0x25: "l", 0x26: "j", 0x27: "'",
        0x28: "k", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "n", 0x2E: "m", 0x2F: ".",
        0x30: "tab", 0x31: "space", 0x33: "delete", 0x35: "escape", 0x7B: "leftarrow",
        0x7C: "rightarrow", 0x7D: "downarrow", 0x7E: "uparrow"
    ]

    private static let namedPhysicalKeys: Set<String> = [
        "return", "tab", "space", "delete", "escape", "leftarrow", "rightarrow", "downarrow", "uparrow"
    ]

    init?(from event: NSEvent) {
        let keyWithoutModifiers = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let keyWithModifiers = event.characters?.lowercased() ?? ""
        let physicalKey = Self.physicalKeyMap[event.keyCode]

        let resolvedKey: String
        if keyWithoutModifiers == "=", keyWithModifiers == "+" {
            resolvedKey = "+"
        } else if let physicalKey, Self.namedPhysicalKeys.contains(physicalKey) {
            resolvedKey = physicalKey
        } else if !keyWithoutModifiers.isEmpty, keyWithoutModifiers.canBeConverted(to: .ascii) {
            resolvedKey = keyWithoutModifiers
        } else if let physicalKey {
            resolvedKey = physicalKey
        } else if !keyWithModifiers.isEmpty {
            resolvedKey = keyWithModifiers
        } else {
            return nil
        }

        self.key = resolvedKey
        self.modifiers = Modifiers(eventModifierFlags: event.modifierFlags)
    }
}

struct Modifiers: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let command = Modifiers(rawValue: 1 << 0)
    static let option = Modifiers(rawValue: 1 << 1)
    static let control = Modifiers(rawValue: 1 << 2)
    static let shift = Modifiers(rawValue: 1 << 3)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(eventModifierFlags: NSEvent.ModifierFlags) {
        var modifiers: Modifiers = []
        if eventModifierFlags.contains(.command) { modifiers.insert(.command) }
        if eventModifierFlags.contains(.option) { modifiers.insert(.option) }
        if eventModifierFlags.contains(.control) { modifiers.insert(.control) }
        if eventModifierFlags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }

    var displayStrings: [String] {
        var strings: [String] = []
        if contains(.command) { strings.append("⌘") }
        if contains(.option) { strings.append("⌥") }
        if contains(.control) { strings.append("⌃") }
        if contains(.shift) { strings.append("⇧") }
        return strings
    }
}
