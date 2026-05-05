import AppKit
import Foundation
import XCTest
@testable import Sumi

@MainActor
final class KeyboardShortcutManagerTests: XCTestCase {
    private let shortcutsKey = "keyboard.shortcuts"
    private let shortcutsVersionKey = "keyboard.shortcuts.version"
    private var originalShortcutsData: Data?
    private var originalVersion: Any?
    private var testDefaults: UserDefaults!
    private var testDefaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        originalShortcutsData = UserDefaults.standard.data(forKey: shortcutsKey)
        originalVersion = UserDefaults.standard.object(forKey: shortcutsVersionKey)
        testDefaultsSuiteName = "KeyboardShortcutManagerTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testDefaultsSuiteName)!
        testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
        testDefaults = nil
        testDefaultsSuiteName = nil

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

    private func makeManager() -> KeyboardShortcutManager {
        KeyboardShortcutManager(userDefaults: testDefaults, installEventMonitor: false)
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
        testDefaults.set(Data(json.utf8), forKey: shortcutsKey)
        testDefaults.set(7, forKey: shortcutsVersionKey)

        let manager = makeManager()

        XCTAssertEqual(
            manager.shortcuts.first { $0.action == .openCommandPalette }?.keyCombination,
            KeyCombination(key: "p", modifiers: [.command, .shift])
        )
        XCTAssertEqual(
            manager.shortcuts.first { $0.action == .copyCurrentURL }?.keyCombination,
            KeyCombination(key: "c", modifiers: [.command, .shift])
        )

        let persistedData = try XCTUnwrap(testDefaults.data(forKey: shortcutsKey))
        let persistedJSON = try XCTUnwrap(String(data: persistedData, encoding: .utf8))
        XCTAssertFalse(persistedJSON.contains("toggle_pip"))
    }

    func testConflictingShortcutDoesNotOverwriteExistingAction() {
        let manager = makeManager()
        let existingNewTab = manager.shortcut(for: .newTab)?.keyCombination

        XCTAssertFalse(
            manager.updateShortcut(
                action: .duplicateTab,
                keyCombination: KeyCombination(key: "t", modifiers: [.command])
            )
        )

        XCTAssertEqual(manager.shortcut(for: .newTab)?.keyCombination, existingNewTab)
        XCTAssertEqual(
            manager.shortcut(for: .duplicateTab)?.keyCombination,
            KeyCombination(key: "d", modifiers: [.option])
        )
    }

    func testClearingShortcutKeepsActionVisible() throws {
        let manager = makeManager()

        XCTAssertTrue(manager.clearShortcut(action: .viewHistory))

        let cleared = try XCTUnwrap(manager.shortcutRecord(for: .viewHistory))
        XCTAssertTrue(cleared.keyCombination.isEmpty)
        XCTAssertFalse(cleared.isEnabled)
        XCTAssertTrue(manager.shortcuts.contains { $0.action == .viewHistory })
        XCTAssertNil(manager.shortcut(for: .viewHistory))
    }

    func testResetRestoresVisibleDefaultActions() {
        let manager = makeManager()
        XCTAssertTrue(manager.clearShortcut(action: .viewHistory))

        manager.resetToDefaults()

        let visibleDefaultActions = Set(KeyboardShortcut.defaultShortcuts.map(\.action))
            .subtracting([.toggleTopBarAddressView])
        XCTAssertEqual(Set(manager.shortcuts.map(\.action)), visibleDefaultActions)
        XCTAssertEqual(
            manager.shortcut(for: .viewHistory)?.keyCombination,
            KeyCombination(key: "y", modifiers: [.command])
        )
    }

    func testCommandMIsNotAssignedToMuteByDefault() throws {
        let manager = makeManager()

        let muteShortcut = try XCTUnwrap(manager.shortcutRecord(for: .muteUnmuteAudio))
        XCTAssertTrue(muteShortcut.keyCombination.isEmpty)
        XCTAssertFalse(muteShortcut.isEnabled)
        XCTAssertNil(manager.shortcut(for: .muteUnmuteAudio))
    }

    func testKeyCombinationParsingUsesPhysicalKeysAndIgnoresCapsLock() throws {
        XCTAssertEqual(
            try XCTUnwrap(Self.keyCombination(keyCode: 0x21, characters: "[", charactersIgnoringModifiers: "[", modifiers: [.command])),
            KeyCombination(key: "[", modifiers: [.command])
        )
        XCTAssertEqual(
            try XCTUnwrap(Self.keyCombination(keyCode: 0x1E, characters: "]", charactersIgnoringModifiers: "]", modifiers: [.command])),
            KeyCombination(key: "]", modifiers: [.command])
        )
        XCTAssertEqual(
            try XCTUnwrap(Self.keyCombination(keyCode: 0x18, characters: "+", charactersIgnoringModifiers: "=", modifiers: [.command, .shift])),
            KeyCombination(key: "+", modifiers: [.command, .shift])
        )
        XCTAssertEqual(
            try XCTUnwrap(Self.keyCombination(keyCode: 0x1B, characters: "-", charactersIgnoringModifiers: "-", modifiers: [.command])),
            KeyCombination(key: "-", modifiers: [.command])
        )
        XCTAssertEqual(
            try XCTUnwrap(Self.keyCombination(keyCode: 0x30, characters: "\t", charactersIgnoringModifiers: "\t", modifiers: [.control])),
            KeyCombination(key: "tab", modifiers: [.control])
        )
        XCTAssertEqual(
            try XCTUnwrap(Self.keyCombination(keyCode: 0x7B, characters: "", charactersIgnoringModifiers: "", modifiers: [.command, .capsLock])),
            KeyCombination(key: "leftarrow", modifiers: [.command])
        )
        XCTAssertEqual(
            try XCTUnwrap(Self.keyCombination(keyCode: 0x35, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", modifiers: [])),
            KeyCombination(key: "escape")
        )
        XCTAssertEqual(
            try XCTUnwrap(Self.keyCombination(keyCode: 0x33, characters: "\u{8}", charactersIgnoringModifiers: "\u{8}", modifiers: [])),
            KeyCombination(key: "delete")
        )
        XCTAssertEqual(
            try XCTUnwrap(Self.keyCombination(keyCode: 0x24, characters: "\r", charactersIgnoringModifiers: "\r", modifiers: [])),
            KeyCombination(key: "return")
        )
    }

    private static func keyCombination(
        keyCode: UInt16,
        characters: String,
        charactersIgnoringModifiers: String,
        modifiers: NSEvent.ModifierFlags
    ) -> KeyCombination? {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        )
        return event.flatMap(KeyCombination.init(from:))
    }
}
