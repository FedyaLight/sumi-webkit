import AppKit
import XCTest

@testable import Sumi
import SumiDomain

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
            ),
        ]
        defaults.set(try JSONEncoder().encode(overrides), forKey: "keyboard.shortcuts")

        let store = KeyboardShortcutStore(userDefaults: defaults)
        XCTAssertNil(store.loadOverrides())
        XCTAssertNil(defaults.data(forKey: "keyboard.shortcuts"))
    }

    @MainActor
    func testToastShortcutPresentationUsesCurrentShortcutManagerValue() {
        let suiteName = "KeyboardShortcutStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults,
            installEventMonitor: false
        )

        XCTAssertEqual(shortcutManager.shortcutDisplayString(for: .undoCloseTab), "⇧⌘T")

        let validation = shortcutManager.setShortcut(
            action: .undoCloseTab,
            keyCombination: KeyCombination(key: "z", modifiers: [.command, .option])
        )
        XCTAssertEqual(validation, .valid)
        XCTAssertEqual(shortcutManager.shortcutDisplayString(for: .undoCloseTab), "⌥⌘Z")

        let notification = BrowserNotification.tabClosure(count: 1, undoShortcut: "⌥⌘Z", action: nil)
        XCTAssertEqual(notification.subtitle, "Press ⌥⌘Z to reopen")
    }

    @MainActor
    func testRegisteredShortcutPassesThroughWhenActionRouterIsDetached() throws {
        let suiteName = "KeyboardShortcutStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults,
            installEventMonitor: false
        )
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: false,
            keyCode: 17
        ))

        XCTAssertFalse(shortcutManager.executeShortcut(event))
    }
}
