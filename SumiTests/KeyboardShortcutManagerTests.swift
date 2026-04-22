import Foundation
import XCTest
@testable import Sumi

@MainActor
final class KeyboardShortcutManagerTests: XCTestCase {
    private let shortcutsKey = "keyboard.shortcuts"
    private let shortcutsVersionKey = "keyboard.shortcuts.version"
    private var originalShortcutsData: Data?
    private var originalVersion: Any?

    override func setUp() {
        super.setUp()
        originalShortcutsData = UserDefaults.standard.data(forKey: shortcutsKey)
        originalVersion = UserDefaults.standard.object(forKey: shortcutsVersionKey)
    }

    override func tearDown() {
        if let originalShortcutsData {
            UserDefaults.standard.set(originalShortcutsData, forKey: shortcutsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: shortcutsKey)
        }

        if let originalVersion {
            UserDefaults.standard.set(originalVersion, forKey: shortcutsVersionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: shortcutsVersionKey)
        }

        super.tearDown()
    }

    func testLegacyPiPShortcutIsDroppedWithoutDiscardingOtherShortcuts() throws {
        let persistedShortcuts = [
            """
            {
              "id":"\(UUID().uuidString)",
              "action":"toggle_pip",
              "keyCombination":{"key":"p","modifiers":{"rawValue":9}},
              "isEnabled":true,
              "isCustomizable":true
            }
            """,
            """
            {
              "id":"\(UUID().uuidString)",
              "action":"copy_current_url",
              "keyCombination":{"key":"c","modifiers":{"rawValue":9}},
              "isEnabled":true,
              "isCustomizable":true
            }
            """,
        ].joined(separator: ",")

        let json = "[\(persistedShortcuts)]"
        UserDefaults.standard.set(Data(json.utf8), forKey: shortcutsKey)
        UserDefaults.standard.set(7, forKey: shortcutsVersionKey)

        let manager = KeyboardShortcutManager()

        XCTAssertEqual(
            manager.shortcuts.first { $0.action == .openCommandPalette }?.keyCombination,
            KeyCombination(key: "p", modifiers: [.command, .shift])
        )
        XCTAssertEqual(
            manager.shortcuts.first { $0.action == .copyCurrentURL }?.keyCombination,
            KeyCombination(key: "c", modifiers: [.command, .shift])
        )

        let persistedData = try XCTUnwrap(UserDefaults.standard.data(forKey: shortcutsKey))
        let persistedJSON = try XCTUnwrap(String(data: persistedData, encoding: .utf8))
        XCTAssertFalse(persistedJSON.contains("toggle_pip"))
    }
}
