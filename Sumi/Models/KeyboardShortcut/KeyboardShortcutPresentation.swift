import AppKit
import SwiftUI
import SumiDomain

enum KeyboardShortcutPresentation {
    /// One glyph per key the user presses, in menu order (⌃⌥⇧⌘ then the key).
    /// Surfaces that draw a chip per key read this; `displayString` is the same
    /// vocabulary joined for menus and recorders.
    static func glyphs(for keyCombination: KeyCombination) -> [String] {
        keyCombination.modifiers.orderedMenuGlyphs + [displayKey(for: keyCombination.key)]
    }

    static func displayString(for keyCombination: KeyCombination) -> String {
        glyphs(for: keyCombination).joined()
    }

    static func keyEquivalent(for keyCombination: KeyCombination) -> KeyEquivalent? {
        switch keyCombination.key.lowercased() {
        case "return", "enter":
            return .return
        case "escape", "esc":
            return .escape
        case "delete", "backspace":
            return .delete
        case "tab":
            return .tab
        case "space":
            return .space
        case "up", "uparrow":
            return .upArrow
        case "down", "downarrow":
            return .downArrow
        case "left", "leftarrow":
            return .leftArrow
        case "right", "rightarrow":
            return .rightArrow
        case "home":
            return .home
        case "end":
            return .end
        case "pageup":
            return .pageUp
        case "pagedown":
            return .pageDown
        case "clear":
            return .clear
        default:
            guard keyCombination.key.count == 1,
                  let character = keyCombination.key.first else {
                return nil
            }
            return KeyEquivalent(character)
        }
    }

    static func eventModifiers(for modifiers: Modifiers) -> EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }

    private static func displayKey(for key: String) -> String {
        switch key.lowercased() {
        case "return", "enter":
            return "↩"
        case "escape", "esc":
            return "Esc"
        case "delete", "backspace":
            return "⌫"
        case "tab":
            return "⇥"
        case "space":
            return "Space"
        case "up", "uparrow":
            return "↑"
        case "down", "downarrow":
            return "↓"
        case "left", "leftarrow":
            return "←"
        case "right", "rightarrow":
            return "→"
        default:
            return key.uppercased()
        }
    }
}

extension Modifiers {
    var orderedMenuGlyphs: [String] {
        var glyphs: [String] = []
        if contains(.control) { glyphs.append("⌃") }
        if contains(.option) { glyphs.append("⌥") }
        if contains(.shift) { glyphs.append("⇧") }
        if contains(.command) { glyphs.append("⌘") }
        return glyphs
    }

    var menuGlyphs: String {
        orderedMenuGlyphs.joined()
    }

    var nsEventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }
}
