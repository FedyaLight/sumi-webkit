import Foundation
import SumiDomain

struct KeyboardShortcut: Hashable, Codable, Sendable {
    let action: ShortcutAction
    var keyCombination: KeyCombination?

    var lookupKey: String? {
        keyCombination?.lookupKey
    }
}
