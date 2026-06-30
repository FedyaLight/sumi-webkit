import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowLifecycleOwnerTests: XCTestCase {
    func testAttachInstallsCallbacksAndSetsUpExistingWindowsOnce() {
        let registry = WindowRegistry()
        let existingWindow = BrowserWindowState()
        let owner = BrowserWindowLifecycleOwner()
        var setupWindowIds: [UUID] = []

        registry.register(existingWindow)

        let firstAttach = owner.attachIfNeeded(
            dependencies: makeDependencies(
                windowRegistry: registry,
                setupWindowState: { setupWindowIds.append($0.id) }
            )
        )
        let secondAttach = owner.attachIfNeeded(dependencies: makeDependencies(windowRegistry: registry))

        XCTAssertTrue(firstAttach)
        XCTAssertFalse(secondAttach)
        XCTAssertNotNil(registry.onWindowRegister)
        XCTAssertNotNil(registry.onWindowClose)
        XCTAssertNotNil(registry.onActiveWindowChange)
        XCTAssertNotNil(registry.onWindowVisibilityChange)
        XCTAssertNotNil(registry.onAllWindowsClosed)
        XCTAssertEqual(setupWindowIds, [existingWindow.id])

        let newWindow = BrowserWindowState()
        registry.register(newWindow)

        XCTAssertEqual(setupWindowIds, [existingWindow.id, newWindow.id])
    }

    func testWindowCloseRunsCleanupBeforeRegistryRemovesWindow() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        let owner = BrowserWindowLifecycleOwner()
        var events: [String] = []

        registry.register(window)
        owner.attachIfNeeded(
            dependencies: makeDependencies(
                windowRegistry: registry,
                handleWindowWillClose: { windowId in
                    events.append("history:\(registry.windows[windowId] != nil)")
                },
                notifyWindowClosedIfLoaded: { _ in events.append("extensions") },
                cleanupWebViews: { _ in events.append("webViews") },
                cleanupSplitWindow: { _ in events.append("split") },
                scheduleWindowClosedMediaReconcile: { events.append("media") },
                windowState: { registry.windows[$0] }
            )
        )

        registry.unregister(window.id)

        XCTAssertEqual(events, ["history:true", "extensions", "webViews", "split", "media"])
        XCTAssertNil(registry.windows[window.id])
    }

    func testIncognitoCloseUsesWindowSnapshotBeforeRemoval() async {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        let owner = BrowserWindowLifecycleOwner()
        let closeExpectation = expectation(description: "incognito window closed")
        var closedWindowIds: [UUID] = []

        window.isIncognito = true
        registry.register(window)
        owner.attachIfNeeded(
            dependencies: makeDependencies(
                windowRegistry: registry,
                windowState: { registry.windows[$0] },
                closeIncognitoWindow: { windowState in
                    closedWindowIds.append(windowState.id)
                    closeExpectation.fulfill()
                }
            )
        )

        registry.unregister(window.id)

        await fulfillment(of: [closeExpectation], timeout: 1)
        XCTAssertEqual(closedWindowIds, [window.id])
    }

    func testAllWindowsClosedRunsSessionCleanupBeforeSiteDataCleanup() async {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        let owner = BrowserWindowLifecycleOwner()
        let siteDataExpectation = expectation(description: "site data cleanup")
        var events: [String] = []

        registry.register(window)
        owner.attachIfNeeded(
            dependencies: makeDependencies(
                windowRegistry: registry,
                prepareForAllWindowsClosed: {
                    events.append("session")
                },
                performSiteDataPolicyAllWindowsClosedCleanup: {
                    events.append("siteData")
                    siteDataExpectation.fulfill()
                }
            )
        )

        registry.unregister(window.id)

        await fulfillment(of: [siteDataExpectation], timeout: 1)
        XCTAssertEqual(events, ["session", "siteData"])
    }

    func testWindowCloseAfterRuntimeDeallocationUsesMinimalCleanupOnly() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        let owner = BrowserWindowLifecycleOwner()
        var events: [String] = []

        registry.register(window)
        owner.attachIfNeeded(
            dependencies: makeDependencies(
                windowRegistry: registry,
                browserRuntimeIsAvailable: { false },
                handleWindowWillClose: { _ in events.append("history") },
                notifyWindowClosedIfLoaded: { _ in events.append("extensions") },
                cleanupWebViews: { _ in events.append("webViews") },
                cleanupSplitWindow: { _ in events.append("split") },
                scheduleWindowClosedMediaReconcile: { events.append("media") },
                cleanupWindowAfterBrowserRuntimeDeallocation: { _ in events.append("fallback") }
            )
        )

        registry.unregister(window.id)

        XCTAssertEqual(events, ["fallback"])
    }

    func testInstalledCallbacksDoNotRetainWindowRegistryThroughDependencyContainer() {
        weak var weakRegistry: WindowRegistry?

        do {
            let registry = WindowRegistry()
            let owner = BrowserWindowLifecycleOwner()
            weakRegistry = registry

            owner.attachIfNeeded(dependencies: makeDependencies(windowRegistry: registry))
        }

        XCTAssertNil(weakRegistry)
    }

    private func makeDependencies(
        windowRegistry: WindowRegistry,
        browserRuntimeIsAvailable: @escaping @MainActor () -> Bool = { true },
        setupWindowState: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
        handleWindowWillClose: @escaping @MainActor (UUID) -> Void = { _ in },
        notifyWindowClosedIfLoaded: @escaping @MainActor (UUID) -> Void = { _ in },
        cleanupWebViews: @escaping @MainActor (UUID) -> Void = { _ in },
        cleanupSplitWindow: @escaping @MainActor (UUID) -> Void = { _ in },
        scheduleWindowClosedMediaReconcile: @escaping @MainActor () -> Void = {},
        windowState: @escaping @MainActor (UUID) -> BrowserWindowState? = { _ in nil },
        closeIncognitoWindow: @escaping @MainActor (BrowserWindowState) async -> Void = { _ in },
        setActiveWindowState: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
        handleWindowVisibilityChanged: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
        prepareForAllWindowsClosed: @escaping @MainActor () -> Void = {},
        performSiteDataPolicyAllWindowsClosedCleanup: @escaping @MainActor () async -> Void = {},
        cleanupWindowAfterBrowserRuntimeDeallocation: @escaping @MainActor (UUID) -> Void = { _ in }
    ) -> BrowserWindowLifecycleOwner.Dependencies {
        BrowserWindowLifecycleOwner.Dependencies(
            windowRegistry: windowRegistry,
            browserRuntimeIsAvailable: browserRuntimeIsAvailable,
            setupWindowState: setupWindowState,
            handleWindowWillClose: handleWindowWillClose,
            notifyWindowClosedIfLoaded: notifyWindowClosedIfLoaded,
            cleanupWebViews: cleanupWebViews,
            cleanupSplitWindow: cleanupSplitWindow,
            scheduleWindowClosedMediaReconcile: scheduleWindowClosedMediaReconcile,
            windowState: windowState,
            closeIncognitoWindow: closeIncognitoWindow,
            setActiveWindowState: setActiveWindowState,
            handleWindowVisibilityChanged: handleWindowVisibilityChanged,
            prepareForAllWindowsClosed: prepareForAllWindowsClosed,
            performSiteDataPolicyAllWindowsClosedCleanup: performSiteDataPolicyAllWindowsClosedCleanup,
            cleanupWindowAfterBrowserRuntimeDeallocation: cleanupWindowAfterBrowserRuntimeDeallocation
        )
    }
}
