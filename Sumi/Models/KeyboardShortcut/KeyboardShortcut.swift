import Foundation

struct KeyboardShortcut: Hashable, Codable {
    let action: ShortcutAction
    var keyCombination: KeyCombination?

    var lookupKey: String? {
        keyCombination?.lookupKey
    }
}
