import Foundation
import SumiDomain

enum ShortcutValidationResult: Equatable {
    case valid
    case invalid
    case conflict(ShortcutAction)
    case namedConflict(String)
    case systemOwned

    var allowsAssignment: Bool {
        switch self {
        case .valid, .conflict, .namedConflict:
            return true
        case .invalid, .systemOwned:
            return false
        }
    }

    var requiresReplacementConfirmation: Bool {
        switch self {
        case .conflict, .namedConflict: return true
        default: return false
        }
    }

    var userMessage: String? {
        switch self {
        case .valid:
            return nil
        case .invalid:
            return "Use ⌘ with letters, ⌘ or ⌃ with numbers, or ⌃Tab."
        case .conflict(let action):
            return "Conflicts with \(action.displayName)."
        case .namedConflict(let title):
            return "Conflicts with \(title)."
        case .systemOwned:
            return "Reserved by macOS or a fixed Sumi menu command."
        }
    }
}

struct ShortcutValidator {
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
        KeyboardCommandAssignments.isValidBrowserActionCombination(
            keyCombination
        )
    }
}
