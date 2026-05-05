import Foundation

struct KeyboardShortcutStore {
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

        guard let overrides = try? JSONDecoder().decode([ShortcutOverride].self, from: data) else {
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

        guard let encoded = try? JSONEncoder().encode(overrides) else { return }
        userDefaults.set(encoded, forKey: shortcutsKey)
    }

    func reset() {
        userDefaults.removeObject(forKey: shortcutsKey)
    }
}
