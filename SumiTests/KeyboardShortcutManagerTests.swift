import AppKit
import XCTest

@testable import Sumi
import SumiDomain

final class KeyboardShortcutManagerTests: XCTestCase {

    @MainActor
    func testToastShortcutPresentationUsesCurrentShortcutManagerValue() {
        let suiteName = "KeyboardShortcutManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults
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
    func testEveryEnabledDefaultShortcutResolvesToItsAction() {
        let suiteName = "KeyboardShortcutManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults
        )

        for shortcut in DefaultKeyboardShortcuts.shortcuts {
            guard let keyCombination = shortcut.keyCombination else { continue }
            XCTAssertEqual(
                shortcutManager.resolvedShortcutAction(for: keyCombination),
                shortcut.action,
                keyCombination.lookupKey
            )
        }
    }

    @MainActor
    func testStandardBrowserKeyEventsResolveFromPhysicalKeys() throws {
        let suiteName = "KeyboardShortcutManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults
        )
        let cases: [(
            key: String,
            keyCode: UInt16,
            modifiers: NSEvent.ModifierFlags,
            action: ShortcutAction
        )] = [
            ("w", 0x0D, [.command], .closeTab),
            ("w", 0x0D, [.command, .shift], .closeWindow),
            ("t", 0x11, [.command], .newTab),
            ("t", 0x11, [.command, .shift], .undoCloseTab),
            ("\t", 0x30, [.control], .nextTab),
            ("\t", 0x30, [.control, .shift], .previousTab),
            ("1", 0x12, [.command], .goToTab1),
            ("2", 0x13, [.command], .goToTab2),
            ("3", 0x14, [.command], .goToTab3),
            ("4", 0x15, [.command], .goToTab4),
            ("5", 0x17, [.command], .goToTab5),
            ("6", 0x16, [.command], .goToTab6),
            ("7", 0x1A, [.command], .goToTab7),
            ("8", 0x1C, [.command], .goToTab8),
            ("9", 0x19, [.command], .goToLastTab),
        ]

        for testCase in cases {
            let event = try XCTUnwrap(
                keyDownEvent(
                    key: testCase.key,
                    keyCode: testCase.keyCode,
                    modifiers: testCase.modifiers
                )
            )
            let combination = try XCTUnwrap(KeyCombination(from: event))
            XCTAssertEqual(
                shortcutManager.resolvedShortcutAction(for: combination),
                testCase.action,
                combination.lookupKey
            )
        }

        XCTAssertNil(
            shortcutManager.resolvedShortcutAction(
                for: KeyCombination(key: ",", modifiers: [.command])
            ),
            "Settings is owned by the native application menu"
        )

        for nativeEditingCombination in [
            KeyCombination(key: "c", modifiers: [.command]),
            KeyCombination(key: "v", modifiers: [.command]),
            KeyCombination(
                key: "v",
                modifiers: [.command, .option, .shift]
            ),
        ] {
            XCTAssertEqual(
                shortcutManager.validate(nativeEditingCombination),
                .systemOwned,
                nativeEditingCombination.lookupKey
            )
        }
    }

    @MainActor
    func testCustomShortcutReplacesDefaultLookup() {
        let suiteName = "KeyboardShortcutManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults
        )
        let replacement = KeyCombination(
            key: "k",
            modifiers: [.command, .option]
        )

        XCTAssertEqual(
            shortcutManager.setShortcut(
                action: .closeTab,
                keyCombination: replacement
            ),
            .valid
        )
        XCTAssertEqual(
            shortcutManager.resolvedShortcutAction(for: replacement),
            .closeTab
        )
        XCTAssertNil(
            shortcutManager.resolvedShortcutAction(
                for: KeyCombination(key: "w", modifiers: [.command])
            )
        )
    }

    @MainActor
    func testMenuCommandUsesExactKeyBrowserWindowInsteadOfStaleActiveWindow() throws {
        let suiteName = "KeyboardShortcutManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = WindowRegistry()
        let browser = BrowserManager(windowRegistry: registry)
        let space = Space(name: "Work")
        browser.spaceStateOwner.replaceSpaces([space])
        browser.spaceStateOwner.replaceCurrentSpace(space)
        browser.structuralCollectionMutationOwner.setTabs([], for: space.id)
        browser.startupRestoreLifecycle.markLoadFinished()

        let staleActiveState = BrowserWindowState()
        staleActiveState.currentSpaceId = space.id
        let keyWindowState = BrowserWindowState()
        keyWindowState.currentSpaceId = space.id
        for windowState in [staleActiveState, keyWindowState] {
            browser.tabResidenceAuthority.establishResidenceSession(
                on: windowState
            )
            XCTAssertEqual(registry.register(windowState), .registered)
        }
        let staleWindow = makeWindow()
        let keyWindow = makeWindow()
        registry.bindAppKitWindow(staleWindow, to: staleActiveState)
        registry.bindAppKitWindow(keyWindow, to: keyWindowState)

        let staleTab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://stale.example",
            in: space,
            activate: false
        )
        let keyTab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://key.example",
            in: space,
            activate: false
        )
        staleActiveState.currentTabId = staleTab.id
        keyWindowState.currentTabId = keyTab.id
        registry.setActive(staleActiveState)

        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults
        )
        shortcutManager.attach(
            actionRouter: browser.shortcutActionRouter,
            targetResolver: browser.shortcutTargetResolver
        )
        XCTAssertTrue(
            shortcutManager.perform(.closeTab, keyWindow: keyWindow)
        )
        XCTAssertIdentical(registry.activeWindow, staleActiveState)
        XCTAssertNotNil(browser.regularTabCollectionOwner.tab(for: staleTab.id))
        XCTAssertNil(browser.regularTabCollectionOwner.tab(for: keyTab.id))
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
    }

    private func keyDownEvent(
        key: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
