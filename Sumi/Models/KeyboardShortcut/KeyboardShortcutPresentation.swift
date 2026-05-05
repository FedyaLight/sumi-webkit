import AppKit
import SwiftUI

enum KeyboardShortcutPresentation {
    static func keyEquivalent(for keyCombination: KeyCombination) -> KeyEquivalent? {
        switch keyCombination.key.lowercased() {
        case "":
            return nil
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

    static func nsMenuKeyEquivalent(for keyCombination: KeyCombination) -> String? {
        switch keyCombination.key.lowercased() {
        case "":
            return nil
        case "return", "enter":
            return "\r"
        case "delete", "backspace":
            return "\u{8}"
        case "tab":
            return "\t"
        case "space":
            return " "
        default:
            guard keyCombination.key.count == 1 else { return nil }
            return keyCombination.key.lowercased()
        }
    }
}

extension Modifiers {
    var nsEventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }
}
