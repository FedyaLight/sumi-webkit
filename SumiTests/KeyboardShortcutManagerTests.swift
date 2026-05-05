import AppKit
import Foundation
import XCTest
@testable import Sumi

@MainActor
final class KeyboardShortcutManagerTests: XCTestCase {
    private let shortcutsKey = "keyboard.shortcuts"
    private var testDefaults: UserDefaults!
    private var testDefaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        testDefaultsSuiteName = "KeyboardShortcutManagerTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testDefaultsSuiteName)!
        testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
        testDefaults = nil
        testDefaultsSuiteName = nil
        super.tearDown()
    }

    private func makeManager() -> KeyboardShortcutManager {
        KeyboardShortcutManager(userDefaults: testDefaults, installEventMonitor: false)
    }

    func testDefaultsCreateFullVisibleActionSet() {
        let manager = makeManager()
        let visibleDefaultActions = Set(DefaultKeyboardShortcuts.shortcuts.map(\.action))
            .subtracting(DefaultKeyboardShortcuts.hiddenActions)

        XCTAssertEqual(Set(manager.shortcuts.map(\.action)), visibleDefaultActions)
    }

    func testConflictingShortcutReturnsConflictAndDoesNotOverwriteExistingAction() {
        let manager = makeManager()
        let existingNewTab = manager.shortcut(for: .newTab)?.keyCombination
        let existingDuplicateTab = manager.shortcut(for: .duplicateTab)?.keyCombination

        let result = manager.setShortcut(
            action: .duplicateTab,
            keyCombination: KeyCombination(key: "t", modifiers: [.command])
        )

        XCTAssertEqual(result, .conflict(.newTab))
        XCTAssertEqual(manager.shortcut(for: .newTab)?.keyCombination, existingNewTab)
        XCTAssertEqual(manager.shortcut(for: .duplicateTab)?.keyCombination, existingDuplicateTab)
    }

    func testSystemOwnedShortcutReturnsSystemOwned() {
        let manager = makeManager()
        let existing = manager.shortcutRecord(for: .muteUnmuteAudio)?.keyCombination

        let result = manager.setShortcut(
            action: .muteUnmuteAudio,
            keyCombination: KeyCombination(key: "m", modifiers: [.command])
        )

        XCTAssertEqual(result, .systemOwned)
        XCTAssertEqual(manager.shortcutRecord(for: .muteUnmuteAudio)?.keyCombination, existing)
    }

    func testInvalidShortcutReturnsInvalid() {
        let manager = makeManager()
        let existing = manager.shortcut(for: .viewHistory)?.keyCombination

        let result = manager.setShortcut(
            action: .viewHistory,
            keyCombination: KeyCombination(key: "a")
        )

        XCTAssertEqual(result, .invalid)
        XCTAssertEqual(manager.shortcut(for: .viewHistory)?.keyCombination, existing)
    }

    func testClearingShortcutKeepsActionVisibleAndRemovesRuntimeLookup() throws {
        let manager = makeManager()

        XCTAssertTrue(manager.clearShortcut(action: .viewHistory))

        let cleared = try XCTUnwrap(manager.shortcutRecord(for: .viewHistory))
        XCTAssertNil(cleared.keyCombination)
        XCTAssertTrue(manager.shortcuts.contains { $0.action == .viewHistory })
        XCTAssertNil(manager.shortcut(for: .viewHistory))
        XCTAssertFalse(manager.executeShortcut(try XCTUnwrap(Self.keyEvent(keyCode: 0x10, characters: "y", modifiers: [.command]))))
    }

    func testResetClearsOverridesAndRestoresDefaults() {
        let manager = makeManager()
        XCTAssertEqual(
            manager.setShortcut(action: .viewHistory, keyCombination: KeyCombination(key: "y", modifiers: [.command, .option])),
            .valid
        )
        XCTAssertTrue(manager.clearShortcut(action: .muteUnmuteAudio))

        manager.resetToDefaults()

        XCTAssertEqual(
            manager.shortcut(for: .viewHistory)?.keyCombination,
            KeyCombination(key: "y", modifiers: [.command])
        )
        XCTAssertNil(manager.shortcutRecord(for: .muteUnmuteAudio)?.keyCombination)
        XCTAssertNil(testDefaults.data(forKey: shortcutsKey))
    }

    func testPersistedOverridesRoundTrip() {
        let manager = makeManager()
        XCTAssertEqual(
            manager.setShortcut(action: .viewHistory, keyCombination: KeyCombination(key: "y", modifiers: [.command, .option])),
            .valid
        )
        XCTAssertTrue(manager.clearShortcut(action: .copyCurrentURL))

        let restoredManager = makeManager()

        XCTAssertEqual(
            restoredManager.shortcut(for: .viewHistory)?.keyCombination,
            KeyCombination(key: "y", modifiers: [.command, .option])
        )
        XCTAssertNil(restoredManager.shortcut(for: .copyCurrentURL))
        XCTAssertNil(restoredManager.shortcutRecord(for: .copyCurrentURL)?.keyCombination)
    }

    func testInvalidPersistedOverridesResetToDefaults() throws {
        let json = """
        [
          {
            "action":"view_history",
            "keyCombination":{"key":"m","modifiers":{"rawValue":1}}
          }
        ]
        """
        testDefaults.set(Data(json.utf8), forKey: shortcutsKey)

        let manager = makeManager()

        XCTAssertEqual(
            manager.shortcut(for: .viewHistory)?.keyCombination,
            KeyCombination(key: "y", modifiers: [.command])
        )
        XCTAssertNil(testDefaults.data(forKey: shortcutsKey))
    }

    func testDuplicatePersistedOverridesResetToDefaults() throws {
        let json = """
        [
          {
            "action":"view_history",
            "keyCombination":{"key":"y","modifiers":{"rawValue":3}}
          },
          {
            "action":"view_history",
            "keyCombination":null
          }
        ]
        """
        testDefaults.set(Data(json.utf8), forKey: shortcutsKey)

        let manager = makeManager()

        XCTAssertEqual(
            manager.shortcut(for: .viewHistory)?.keyCombination,
            KeyCombination(key: "y", modifiers: [.command])
        )
        XCTAssertNil(testDefaults.data(forKey: shortcutsKey))
    }

    func testCommandMIsNotAssignedToMuteByDefault() throws {
        let manager = makeManager()

        let muteShortcut = try XCTUnwrap(manager.shortcutRecord(for: .muteUnmuteAudio))
        XCTAssertNil(muteShortcut.keyCombination)
        XCTAssertNil(manager.shortcut(for: .muteUnmuteAudio))
    }

    func testCommandShiftPIsNotRegisteredForCommandPalette() throws {
        let manager = makeManager()
        let commandShiftP = try XCTUnwrap(Self.keyEvent(keyCode: 0x23, characters: "P", modifiers: [.command, .shift]))

        XCTAssertFalse(manager.executeShortcut(commandShiftP))
    }

    func testEnabledLookupUpdatesAfterSetClearAndReset() throws {
        let manager = makeManager()
        let commandOptionY = try XCTUnwrap(Self.keyEvent(keyCode: 0x10, characters: "y", modifiers: [.command, .option]))
        let commandY = try XCTUnwrap(Self.keyEvent(keyCode: 0x10, characters: "y", modifiers: [.command]))

        XCTAssertEqual(
            manager.setShortcut(action: .viewHistory, keyCombination: KeyCombination(key: "y", modifiers: [.command, .option])),
            .valid
        )
        XCTAssertTrue(manager.executeShortcut(commandOptionY))
        XCTAssertFalse(manager.executeShortcut(commandY))

        XCTAssertTrue(manager.clearShortcut(action: .viewHistory))
        XCTAssertFalse(manager.executeShortcut(commandOptionY))

        manager.resetToDefaults()
        XCTAssertTrue(manager.executeShortcut(commandY))
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
        keyEvent(
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifiers: modifiers
        ).flatMap(KeyCombination.init(from:))
    }

    private static func keyEvent(
        keyCode: UInt16,
        characters: String,
        charactersIgnoringModifiers: String? = nil,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
