import XCTest
import WebKit
import SumiWebRuntime

@testable import Sumi

@MainActor
final class BrowserWindowLifecycleOwnerTests: XCTestCase {
    func testAttachInstallsCallbacksAndSetsUpExistingWindowsOnce() {
        let registry = WindowRegistry()
        let existingWindow = BrowserWindowState()
        let owner = BrowserWindowLifecycleOwner()
        var setupWindowIds: [UUID] = []

        registry.register(existingWindow)

        let firstAttach = attach(
            owner,
            windowRegistry: registry,
            setupWindowState: { setupWindowIds.append($0.id) }
        )
        let secondAttach = attach(owner, windowRegistry: registry)

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
        attach(
            owner,
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
        attach(
            owner,
            windowRegistry: registry,
            windowState: { registry.windows[$0] },
            closeIncognitoWindow: { windowState in
                closedWindowIds.append(windowState.id)
                closeExpectation.fulfill()
            }
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
        attach(
            owner,
            windowRegistry: registry,
            prepareForAllWindowsClosed: {
                events.append("session")
            },
            performAllWindowsClosedSiteDataCleanup: {
                events.append("siteData")
                siteDataExpectation.fulfill()
            }
        )

        registry.unregister(window.id)

        await fulfillment(of: [siteDataExpectation], timeout: 1)
        XCTAssertEqual(events, ["session", "siteData"])
    }

    func testWindowCloseAfterRuntimeDeallocationUsesTerminalFallbackOnly() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        let owner = BrowserWindowLifecycleOwner()
        var events: [String] = []

        registry.register(window)
        attach(
            owner,
            windowRegistry: registry,
            browserRuntimeIsAvailable: { false },
            handleWindowWillClose: { _ in events.append("history") },
            notifyWindowClosedIfLoaded: { _ in events.append("extensions") },
            cleanupWebViews: { _ in events.append("webViews") },
            cleanupSplitWindow: { _ in events.append("split") },
            scheduleWindowClosedMediaReconcile: { events.append("media") },
            cleanupWindowAfterRuntimeDeallocation: { _ in events.append("fallback") }
        )

        registry.unregister(window.id)

        XCTAssertEqual(events, ["fallback"])
    }

    func testRuntimeDeallocationFallbackTerminatesEveryCanonicalResidence() throws {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        let owner = BrowserWindowLifecycleOwner()
        var browserManager: BrowserManager? = BrowserManager()
        let repository = try XCTUnwrap(browserManager?.webViewSessions)
        let coordinator = try XCTUnwrap(browserManager?.bindTestWebViewCoordinator())
        let trackedTabID = UUID()
        let parkedTabID = UUID()
        let untrackedTabID = UUID()
        let pendingTabID = UUID()
        let tracked = WKWebView()
        let parked = WKWebView()
        let untracked = WKWebView()
        let pending = WKWebView()
        let trackedTab = Tab(
            id: trackedTabID,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )

        coordinator.ownershipService.registerTrackedWebView(
            tracked,
            for: trackedTab,
            in: window.id
        )
        WebViewSessionHandle(
            tabID: parkedTabID,
            repository: repository
        ).park(parked)
        WebViewSessionHandle(
            tabID: untrackedTabID,
            repository: repository
        ).replaceUntracked(with: untracked)
        XCTAssertNotNil(repository.beginPendingCleanup(of: pending, for: pendingTabID))
        coordinator.protectionRuntime.beginHistorySwipe(
            tabID: trackedTabID,
            webView: tracked,
            originURL: nil,
            originHistoryItem: nil
        )
        XCTAssertTrue(
            coordinator.protectionRuntime.hasActiveHistorySwipe(in: window.id)
        )

        registry.register(window)
        weak var releasedBrowserManager = browserManager
        browserManager = nil
        XCTAssertNil(releasedBrowserManager)
        attach(
            owner,
            windowRegistry: registry,
            browserRuntimeIsAvailable: { false },
            cleanupWindowAfterRuntimeDeallocation: { _ in
                coordinator.lifecycleService
                    .cleanupAfterBrowserRuntimeDeallocation()
            }
        )

        registry.unregister(window.id)

        XCTAssertTrue(repository.queries.isTrackingEmpty)
        for webView in [tracked, parked, untracked, pending] {
            XCTAssertNil(repository.residence(of: webView))
        }
        XCTAssertFalse(
            coordinator.protectionRuntime.hasActiveHistorySwipe(in: window.id)
        )
        XCTAssertNil(coordinator.runtimeContextStore.environment)
    }

    func testInstalledCallbacksDoNotRetainWindowRegistryThroughDependencyContainer() {
        weak var weakRegistry: WindowRegistry?

        do {
            let registry = WindowRegistry()
            let owner = BrowserWindowLifecycleOwner()
            weakRegistry = registry

            attach(owner, windowRegistry: registry)
        }

        XCTAssertNil(weakRegistry)
    }

    @discardableResult
    private func attach(
        _ owner: BrowserWindowLifecycleOwner,
        windowRegistry: WindowRegistry,
        browserRuntimeIsAvailable: @escaping @MainActor () -> Bool = { true },
        setupWindowState: @escaping @MainActor (BrowserWindowState) -> Void = { _ in /* No-op. */ },
        handleWindowWillClose: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ },
        notifyWindowClosedIfLoaded: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ },
        cleanupWebViews: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ },
        cleanupSplitWindow: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ },
        scheduleWindowClosedMediaReconcile: @escaping @MainActor () -> Void = { /* No-op. */ },
        windowState: @escaping @MainActor (UUID) -> BrowserWindowState? = { _ in nil },
        closeIncognitoWindow: @escaping @MainActor (BrowserWindowState) async -> Void = { _ in /* No-op. */ },
        setActiveWindowState: @escaping @MainActor (BrowserWindowState) -> Void = { _ in /* No-op. */ },
        handleWindowVisibilityChanged: @escaping @MainActor (BrowserWindowState) -> Void = { _ in /* No-op. */ },
        prepareForAllWindowsClosed: @escaping @MainActor () -> Void = { /* No-op. */ },
        performAllWindowsClosedSiteDataCleanup: @escaping @MainActor () async -> Void = { /* No-op. */ },
        cleanupWindowAfterRuntimeDeallocation: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ }
    ) -> Bool {
        owner.attachIfNeeded(
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
            performAllWindowsClosedSiteDataCleanup: performAllWindowsClosedSiteDataCleanup,
            cleanupWindowAfterRuntimeDeallocation: cleanupWindowAfterRuntimeDeallocation
        )
    }
}
