import Foundation

enum ShortcutValidationResult: Equatable {
    case valid
    case invalid
    case conflict(ShortcutAction)
    case systemOwned

    var allowsCommit: Bool {
        self == .valid
    }

    var userMessage: String? {
        switch self {
        case .valid:
            return nil
        case .invalid:
            return "Use a key with a modifier, or a supported special key."
        case .conflict(let action):
            return "Conflicts with \(action.displayName)."
        case .systemOwned:
            return "Reserved by macOS."
        }
    }
}

struct ShortcutValidator {
    private static let modifierOptionalKeys: Set<String> = [
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
        "escape", "delete", "forwarddelete", "home", "end", "pageup", "pagedown",
        "help", "tab", "return", "space", "uparrow", "downarrow", "leftarrow", "rightarrow"
    ]

    let systemOwnedShortcuts: Set<KeyCombination>

    func validate(
        _ keyCombination: KeyCombination,
        in shortcutsByAction: [ShortcutAction: KeyboardShortcut],
        excludingAction: ShortcutAction? = nil
    ) -> ShortcutValidationResult {
        guard isValidKeyCombination(keyCombination) else {
            return .invalid
        }
        guard !systemOwnedShortcuts.contains(keyCombination) else {
            return .systemOwned
        }
        if let conflict = conflict(for: keyCombination, in: shortcutsByAction, excludingAction: excludingAction) {
            return .conflict(conflict)
        }
        return .valid
    }

    func conflict(
        for keyCombination: KeyCombination,
        in shortcutsByAction: [ShortcutAction: KeyboardShortcut],
        excludingAction: ShortcutAction? = nil
    ) -> ShortcutAction? {
        guard !keyCombination.key.isEmpty else { return nil }
        for shortcut in shortcutsByAction.values {
            guard let combination = shortcut.keyCombination,
                  combination.lookupKey == keyCombination.lookupKey,
                  shortcut.action != excludingAction else {
                continue
            }
            return shortcut.action
        }
        return nil
    }

    func isValidKeyCombination(_ keyCombination: KeyCombination) -> Bool {
        guard !keyCombination.key.isEmpty else { return false }

        if Self.modifierOptionalKeys.contains(keyCombination.key.lowercased()) {
            return true
        }

        return !keyCombination.modifiers.isEmpty
    }
}
