import Foundation
import OSLog

struct KeyboardShortcutStore {
    private static let log = Logger.sumi(category: "KeyboardShortcuts")

    private struct ShortcutOverride: Codable, Equatable {
        var action: ShortcutAction
        var keyCombination: KeyCombination?
    }

    private let userDefaults: UserDefaults
    private let shortcutsKey = "keyboard.shortcuts"

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func loadOverrides() -> [ShortcutAction: KeyCombination?]? {
        guard let data = userDefaults.data(forKey: shortcutsKey) else {
            return [:]
        }

        let overrides: [ShortcutOverride]
        do {
            overrides = try JSONDecoder().decode([ShortcutOverride].self, from: data)
        } catch {
            Self.log.error(
                "Failed to decode keyboard shortcuts: \(error.localizedDescription, privacy: .public)"
            )
            reset()
            return nil
        }

        var result: [ShortcutAction: KeyCombination?] = [:]
        var seenActions: Set<ShortcutAction> = []
        for override in overrides {
            guard !seenActions.contains(override.action) else {
                reset()
                return nil
            }
            seenActions.insert(override.action)
            result[override.action] = override.keyCombination
        }
        return result
    }

    func saveOverrides(
        _ shortcutsByAction: [ShortcutAction: KeyboardShortcut],
        defaults: [ShortcutAction: KeyboardShortcut]
    ) {
        let overrides = shortcutsByAction.values
            .filter { shortcut in
                shortcut.keyCombination != defaults[shortcut.action]?.keyCombination
            }
            .map {
                ShortcutOverride(action: $0.action, keyCombination: $0.keyCombination)
            }
            .sorted { $0.action.rawValue < $1.action.rawValue }

        guard !overrides.isEmpty else {
            reset()
            return
        }

        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(overrides)
        } catch {
            Self.log.error(
                "Failed to encode keyboard shortcuts: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        userDefaults.set(encoded, forKey: shortcutsKey)
    }

    func reset() {
        userDefaults.removeObject(forKey: shortcutsKey)
    }
}
