import AppKit
import Foundation
import SumiDomain

extension KeyCombination {
    private static let physicalKeyMap: [UInt16: String] = [
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g", 0x06: "z", 0x07: "x",
        0x08: "c", 0x09: "v", 0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y",
        0x11: "t", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "o", 0x20: "u",
        0x21: "[", 0x22: "i", 0x23: "p", 0x24: "return", 0x25: "l", 0x26: "j", 0x27: "'",
        0x28: "k", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "n", 0x2E: "m", 0x2F: ".",
        0x30: "tab", 0x31: "space", 0x33: "delete", 0x35: "escape", 0x7B: "leftarrow",
        0x7C: "rightarrow", 0x7D: "downarrow", 0x7E: "uparrow",
        0x72: "insert", 0x73: "home", 0x74: "pageup", 0x75: "delete",
        0x77: "end", 0x79: "pagedown",
        0x7A: "f1", 0x78: "f2", 0x63: "f3", 0x76: "f4",
        0x60: "f5", 0x61: "f6", 0x62: "f7", 0x64: "f8",
        0x65: "f9", 0x6D: "f10", 0x67: "f11", 0x6F: "f12",
    ]

    private static let namedPhysicalKeys: Set<String> = [
        "return", "tab", "space", "delete", "escape", "leftarrow", "rightarrow", "downarrow", "uparrow",
        "insert", "home", "end", "pageup", "pagedown",
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9",
        "f10", "f11", "f12",
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

        self.init(key: resolvedKey, modifiers: Modifiers(eventModifierFlags: event.modifierFlags))
    }
}

extension Modifiers {
    init(eventModifierFlags: NSEvent.ModifierFlags) {
        var modifiers: Modifiers = []
        if eventModifierFlags.contains(.command) { modifiers.insert(.command) }
        if eventModifierFlags.contains(.option) { modifiers.insert(.option) }
        if eventModifierFlags.contains(.control) { modifiers.insert(.control) }
        if eventModifierFlags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }
}
