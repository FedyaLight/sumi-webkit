import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserZoomCommandOwnerTests: XCTestCase {
    func testZoomInActiveTabSavesProfileScopedBaseZoomAppliesBoostAndRequestsMenuPopover() {
        let zoomManager = makeZoomManager()
        let profileId = UUID()
        let tab = makeTab(url: "https://example.com/page", profileId: profileId)
        let webView = WKWebView()
        let windowState = BrowserWindowState()
        var revision = 0
        var popoverRequest: ZoomPopoverRequest?
        var boostRequest: (url: URL, profileId: UUID?)?

        let owner = makeOwner(
            zoomManager: zoomManager,
            activeWindow: { windowState },
            activePageTab: { _ in tab },
            activePageWebView: { _ in webView },
            sizeOverride: { url, profileId in
                boostRequest = (url, profileId)
                return 2.0
            },
            incrementZoomStateRevision: {
                revision += 1
            },
            setZoomPopoverRequest: { request in
                popoverRequest = request
            }
        )

        owner.zoomInCurrentTab()

        XCTAssertEqual(zoomManager.getZoomLevel(for: "example.com", profileId: profileId), 1.15, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 2.3, accuracy: 0.001)
        XCTAssertEqual(zoomManager.getZoomLevel(for: tab.id), 2.3, accuracy: 0.001)
        XCTAssertEqual(revision, 1)
        XCTAssertEqual(popoverRequest?.windowId, windowState.id)
        XCTAssertEqual(popoverRequest?.tabId, tab.id)
        XCTAssertEqual(popoverRequest?.source, .menu)
        XCTAssertEqual(boostRequest?.url, tab.url)
        XCTAssertEqual(boostRequest?.profileId, profileId)
    }

    func testLoadZoomForTabUsesContainingWindowBeforeActiveWindowAndDoesNotRequestPopover() {
        let zoomManager = makeZoomManager()
        let profileId = UUID()
        let tab = makeTab(url: "https://example.com/page", profileId: profileId)
        let webView = WKWebView()
        let activeWindow = BrowserWindowState()
        let containingWindow = BrowserWindowState()
        var requestedWebViewWindowId: UUID?
        var revision = 0
        var popoverRequest: ZoomPopoverRequest?

        zoomManager.saveZoomLevel(1.5, for: "example.com", profileId: profileId)

        let owner = makeOwner(
            zoomManager: zoomManager,
            activeWindow: { activeWindow },
            tab: { requestedTabId in
                requestedTabId == tab.id ? tab : nil
            },
            windowStateContainingTab: { _ in containingWindow },
            webView: { requestedTabId, windowId in
                requestedWebViewWindowId = windowId
                return requestedTabId == tab.id && windowId == containingWindow.id ? webView : nil
            },
            incrementZoomStateRevision: {
                revision += 1
            },
            setZoomPopoverRequest: { request in
                popoverRequest = request
            }
        )

        owner.loadZoomForTab(tab.id)

        XCTAssertEqual(requestedWebViewWindowId, containingWindow.id)
        XCTAssertEqual(webView.pageZoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(zoomManager.getZoomLevel(for: tab.id), 1.5, accuracy: 0.001)
        XCTAssertEqual(revision, 1)
        XCTAssertNil(popoverRequest)
    }

    func testCleanupRemovesTabZoomAndBumpsRevision() {
        let zoomManager = makeZoomManager()
        let tabId = UUID()
        let webView = WKWebView()
        var revision = 0

        zoomManager.applyTransientZoom(1.5, to: webView, domain: "example.com", tabId: tabId)

        let owner = makeOwner(
            zoomManager: zoomManager,
            incrementZoomStateRevision: {
                revision += 1
            }
        )

        owner.cleanupZoomForTab(tabId)

        XCTAssertEqual(zoomManager.getZoomLevel(for: tabId), 1.0, accuracy: 0.001)
        XCTAssertEqual(revision, 1)
    }

    private func makeZoomManager(function: String = #function) -> ZoomManager {
        let suiteName = "BrowserZoomCommandOwnerTests.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return ZoomManager(userDefaults: defaults)
    }

    private func makeOwner(
        zoomManager: ZoomManager,
        activeWindow: @escaping @MainActor () -> BrowserWindowState? = { nil },
        activePageTab: @escaping @MainActor (BrowserWindowState) -> Tab? = { _ in nil },
        activePageWebView: @escaping @MainActor (BrowserWindowState) -> WKWebView? = { _ in nil },
        tab: @escaping @MainActor (UUID) -> Tab? = { _ in nil },
        windowStateContainingTab: @escaping @MainActor (Tab) -> BrowserWindowState? = { _ in nil },
        webView: @escaping @MainActor (UUID, UUID) -> WKWebView? = { _, _ in nil },
        sizeOverride: @escaping @MainActor (URL, UUID?) -> Double = { _, _ in 1.0 },
        incrementZoomStateRevision: @escaping @MainActor () -> Void = {},
        setZoomPopoverRequest: @escaping @MainActor (ZoomPopoverRequest) -> Void = { _ in }
    ) -> BrowserZoomCommandOwner {
        BrowserZoomCommandOwner(
            dependencies: BrowserZoomCommandOwner.Dependencies(
                activeWindow: activeWindow,
                activePageTab: activePageTab,
                activePageWebView: activePageWebView,
                tab: tab,
                windowStateContainingTab: windowStateContainingTab,
                webView: webView,
                zoomManager: { zoomManager },
                sizeOverride: sizeOverride,
                incrementZoomStateRevision: incrementZoomStateRevision,
                setZoomPopoverRequest: setZoomPopoverRequest
            )
        )
    }

    private func makeTab(url: String, profileId: UUID?) -> Tab {
        let tab = Tab(
            url: URL(string: url)!,
            name: "Test",
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = profileId
        return tab
    }
}
