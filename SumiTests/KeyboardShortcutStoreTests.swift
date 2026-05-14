import XCTest

@testable import Sumi

final class KeyboardShortcutStoreTests: XCTestCase {
    private struct UnknownShortcutOverride: Codable {
        var action: String
        var keyCombination: KeyCombination?
    }

    func testLoadOverridesResetsUnknownActions() throws {
        let suiteName = "KeyboardShortcutStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let overrides = [
            UnknownShortcutOverride(
                action: "unknown_action",
                keyCombination: KeyCombination(key: "l", modifiers: [.command, .option])
            )
        ]
        defaults.set(try JSONEncoder().encode(overrides), forKey: "keyboard.shortcuts")

        let store = KeyboardShortcutStore(userDefaults: defaults)
        XCTAssertNil(store.loadOverrides())
        XCTAssertNil(defaults.data(forKey: "keyboard.shortcuts"))
    }
}
