import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowFocusRuntimeTests: XCTestCase {
    func testActivationMovesActiveRuntimeToFocusedRegularWindow() {
        let browserManager = makeBrowserManager()
        let first = makeLiveWindow(named: "First", in: browserManager)
        let second = makeLiveWindow(named: "Second", in: browserManager)

        browserManager.windowSessionBundle.activation.activate(first.window)

        XCTAssertEqual(first.space.profileRuntimeState, .active)
        XCTAssertEqual(second.space.profileRuntimeState, .loadedInactive)

        browserManager.windowSessionBundle.activation.activate(second.window)

        XCTAssertEqual(first.space.profileRuntimeState, .loadedInactive)
        XCTAssertEqual(second.space.profileRuntimeState, .active)
    }

    func testBackgroundSelectionContextCannotStealFocusedRuntime() {
        let browserManager = makeBrowserManager()
        let focused = makeLiveWindow(named: "Focused", in: browserManager)
        let background = makeLiveWindow(named: "Background", in: browserManager)
        let registry = register(
            [focused.window, background.window],
            active: focused.window,
            in: browserManager
        )

        browserManager.windowSessionBundle.activation.activate(focused.window)
        browserManager.windowStateReconciler.synchronizeSpaceContext(
            in: background.window
        )

        XCTAssertIdentical(registry.activeWindow, focused.window)
        XCTAssertEqual(focused.space.profileRuntimeState, .active)
        XCTAssertEqual(background.space.profileRuntimeState, .loadedInactive)
    }

    func testActiveShortcutSelectionRecomputesFocusedRuntime() {
        let browserManager = makeBrowserManager()
        let focused = makeLiveWindow(named: "Focused", in: browserManager)
        let shortcutSpace = browserManager.tabManager.spaceServices.catalog
            .createSpace(name: "Shortcut only")
        let registry = register(
            [focused.window],
            active: focused.window,
            in: browserManager
        )
        browserManager.windowSessionBundle.activation.activate(focused.window)
        XCTAssertEqual(shortcutSpace.profileRuntimeState, .dormant)

        focused.window.selectedShortcutPinForSpace[shortcutSpace.id] = UUID()
        browserManager.windowStateReconciler.synchronizeSpaceContext(
            in: focused.window
        )

        XCTAssertIdentical(registry.activeWindow, focused.window)
        XCTAssertEqual(focused.space.profileRuntimeState, .active)
        XCTAssertEqual(shortcutSpace.profileRuntimeState, .loadedInactive)
    }

    func testIncognitoActivationClearsRegularActiveRuntimeWithoutRewritingIdentity() {
        let browserManager = makeBrowserManager()
        let regular = makeLiveWindow(named: "Regular", in: browserManager)
        let privateProfileID = UUID()
        let privateSpaceID = UUID()
        let privateWindow = BrowserWindowState()
        privateWindow.isIncognito = true
        privateWindow.currentProfileId = privateProfileID
        privateWindow.currentSpaceId = privateSpaceID

        browserManager.windowSessionBundle.activation.activate(regular.window)
        XCTAssertEqual(regular.space.profileRuntimeState, .active)

        browserManager.windowSessionBundle.activation.activate(privateWindow)

        XCTAssertEqual(regular.space.profileRuntimeState, .loadedInactive)
        XCTAssertEqual(privateWindow.currentProfileId, privateProfileID)
        XCTAssertEqual(privateWindow.currentSpaceId, privateSpaceID)
    }

    func testDeferredActivationKeepsPreviousRuntimeUntilExactWindowResolves() {
        let browserManager = makeBrowserManager()
        let first = makeLiveWindow(named: "First", in: browserManager)
        let deferred = makeLiveWindow(
            named: "Deferred",
            awaitsInitialSessionResolution: true,
            in: browserManager
        )

        browserManager.windowSessionBundle.activation.activate(first.window)
        browserManager.windowSessionBundle.activation.activate(deferred.window)

        XCTAssertEqual(first.space.profileRuntimeState, .active)
        XCTAssertEqual(deferred.space.profileRuntimeState, .loadedInactive)

        deferred.window.restorationState.isAwaitingInitialResolution = false
        browserManager.windowSessionBundle.activation
            .completeDeferredActivation(for: deferred.window)

        XCTAssertEqual(first.space.profileRuntimeState, .loadedInactive)
        XCTAssertEqual(deferred.space.profileRuntimeState, .active)
    }

    private func makeBrowserManager() -> BrowserManager {
        let sessionKey = "SumiTests.focus-runtime.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }
        let browserManager = BrowserManager(
            windowSessionSnapshotStore: WindowSessionSnapshotStore(
                key: sessionKey
            )
        )
        browserManager.tabManager.spaceStateOwner.replaceSpaces([])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(nil)
        return browserManager
    }

    private func makeLiveWindow(
        named name: String,
        awaitsInitialSessionResolution: Bool = false,
        in browserManager: BrowserManager
    ) -> (space: Space, window: BrowserWindowState) {
        let space = browserManager.tabManager.spaceServices.catalog
            .createSpace(name: name)
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://\(name.lowercased()).example",
            in: space,
            activate: false
        )
        let window = BrowserWindowState(
            awaitsInitialSessionResolution: awaitsInitialSessionResolution
        )
        window.tabManager = browserManager.tabManager
        window.currentSpaceId = space.id
        window.currentTabId = tab.id
        window.isShowingEmptyState = false
        return (space, window)
    }

    private func register(
        _ windows: [BrowserWindowState],
        active activeWindow: BrowserWindowState,
        in browserManager: BrowserManager
    ) -> WindowRegistry {
        let registry = WindowRegistry()
        browserManager.windowRegistry = registry
        for window in windows {
            registry.register(window)
        }
        registry.setActive(activeWindow)
        return registry
    }
}
