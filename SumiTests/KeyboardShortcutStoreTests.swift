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

        XCTAssertFalse(
            shortcutManager.executeShortcut(
                event,
                in: BrowserShortcutContext(
                    windowState: BrowserWindowState(),
                    appKitWindow: NSWindow(),
                    page: nil
                )
            )
        )
    }

    @MainActor
    func testEveryEnabledDefaultShortcutResolvesToItsAction() {
        let suiteName = "KeyboardShortcutStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults,
            installEventMonitor: false
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
        let suiteName = "KeyboardShortcutStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults,
            installEventMonitor: false
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
            (",", 0x2B, [.command], .openSettings),
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
    }

    @MainActor
    func testCustomShortcutReplacesDefaultLookup() {
        let suiteName = "KeyboardShortcutStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults,
            installEventMonitor: false
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
    func testCommandWUsesExactKeyBrowserWindowInsteadOfStaleActiveWindow() throws {
        let suiteName = "KeyboardShortcutStoreTests-\(UUID().uuidString)"
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
            userDefaults: defaults,
            installEventMonitor: false
        )
        shortcutManager.attach(
            actionRouter: browser.shortcutActionRouter,
            targetResolver: browser.shortcutTargetResolver,
            extensionsModule: browser.optionalModules.extensions
        )
        let event = try XCTUnwrap(
            keyDownEvent(
                key: "w",
                keyCode: 0x0D,
                modifiers: [.command]
            )
        )

        XCTAssertNil(
            shortcutManager.routeLocalKeyDown(
                event,
                keyWindow: keyWindow
            )
        )
        XCTAssertIdentical(registry.activeWindow, staleActiveState)
        XCTAssertNotNil(browser.regularTabCollectionOwner.tab(for: staleTab.id))
        XCTAssertNil(browser.regularTabCollectionOwner.tab(for: keyTab.id))
    }

    @MainActor
    func testChildWindowShortcutPassesToAppKitResponderChain() throws {
        let suiteName = "KeyboardShortcutStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = WindowRegistry()
        let browser = BrowserManager(windowRegistry: registry)
        let windowState = BrowserWindowState()
        browser.tabResidenceAuthority.establishResidenceSession(on: windowState)
        XCTAssertEqual(registry.register(windowState), .registered)
        let browserWindow = makeWindow()
        let childWindow = makeWindow()
        browserWindow.addChildWindow(childWindow, ordered: .above)
        registry.bindAppKitWindow(browserWindow, to: windowState)
        let shortcutManager = KeyboardShortcutManager(
            userDefaults: defaults,
            installEventMonitor: false
        )
        shortcutManager.attach(
            actionRouter: browser.shortcutActionRouter,
            targetResolver: browser.shortcutTargetResolver,
            extensionsModule: browser.optionalModules.extensions
        )
        let event = try XCTUnwrap(
            keyDownEvent(
                key: "w",
                keyCode: 0x0D,
                modifiers: [.command]
            )
        )

        XCTAssertIdentical(
            shortcutManager.routeLocalKeyDown(
                event,
                keyWindow: childWindow
            ),
            event
        )
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
