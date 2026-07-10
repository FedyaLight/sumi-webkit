import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserZoomCommandOwnerTests: XCTestCase {
    func testZoomInActiveTabSavesProfileScopedBaseZoomAppliesBoostAndPresentsNotification() {
        let zoomManager = makeZoomManager()
        let profileId = UUID()
        let tab = makeTab(url: "https://example.com/page", profileId: profileId)
        let webView = WKWebView()
        let windowState = BrowserWindowState()
        var revision = 0
        let spy = NotificationPresentingSpy()
        var boostRequest: (url: URL, profileId: UUID?)?

        let owner = makeOwner(
            zoomManager: zoomManager,
            activeWindow: { windowState },
            activePageTab: { _ in tab },
            activePresentationWebView: { _ in webView },
            sizeOverride: { url, profileId in
                boostRequest = (url, profileId)
                return 2.0
            },
            incrementZoomStateRevision: {
                revision += 1
            },
            notifications: { spy }
        )

        owner.zoomInCurrentTab()

        XCTAssertEqual(zoomManager.getZoomLevel(for: "example.com", profileId: profileId), 1.15, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 2.3, accuracy: 0.001)
        XCTAssertEqual(zoomManager.getZoomLevel(for: tab.id), 2.3, accuracy: 0.001)
        XCTAssertEqual(revision, 1)
        XCTAssertEqual(spy.presentNotificationCalls.count, 1)
        XCTAssertEqual(spy.presentNotificationCalls.first?.0.messageKey, "zoom")
        XCTAssertEqual(spy.presentNotificationCalls.first?.0.title, "Zoom")
        XCTAssertEqual(spy.presentNotificationCalls.first?.0.controls?.count, 3)
        XCTAssertEqual(spy.presentNotificationCalls.first?.1?.id, windowState.id)
        XCTAssertEqual(boostRequest?.url, tab.url)
        XCTAssertEqual(boostRequest?.profileId, profileId)
    }

    func testLoadZoomForTabUsesContainingWindowBeforeActiveWindowAndDoesNotPresentNotification() {
        let zoomManager = makeZoomManager()
        let profileId = UUID()
        let tab = makeTab(url: "https://example.com/page", profileId: profileId)
        let webView = WKWebView()
        let activeWindow = BrowserWindowState()
        let containingWindow = BrowserWindowState()
        var requestedWebViewWindowId: UUID?
        var revision = 0
        let spy = NotificationPresentingSpy()

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
            notifications: { spy }
        )

        owner.loadZoomForTab(tab.id)

        XCTAssertEqual(requestedWebViewWindowId, containingWindow.id)
        XCTAssertEqual(webView.pageZoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(zoomManager.getZoomLevel(for: tab.id), 1.5, accuracy: 0.001)
        XCTAssertEqual(revision, 1)
        XCTAssertTrue(spy.presentNotificationCalls.isEmpty)
    }

    func testZoomTargetsReaderPresentationWithoutMutatingHiddenCanonicalWebView() {
        let zoomManager = makeZoomManager()
        let tab = makeTab(url: "https://example.com/article", profileId: nil)
        let canonicalWebView = WKWebView()
        canonicalWebView.pageZoom = 1
        let host = SumiWebViewContainerView(tabID: tab.id, webView: canonicalWebView)
        let lease = TabMainFrameDocumentLease(
            revision: 1,
            documentGeneration: 1,
            webViewID: ObjectIdentifier(canonicalWebView),
            participantID: UUID(),
            committedURL: tab.url,
            presentationURL: tab.url,
            isPDF: false,
            isAuthority: true
        )
        XCTAssertTrue(host.presentReader(
            html: "<html><body><article>Reader</article></body></html>",
            sourceURL: tab.url,
            documentLease: lease,
            navigate: { _ in XCTFail("Reader navigation was not requested") }
        ))
        let windowState = BrowserWindowState()
        let owner = makeOwner(
            zoomManager: zoomManager,
            activeWindow: { windowState },
            activePageTab: { _ in tab },
            activePresentationWebView: { _ in canonicalWebView.sumiActivePresentationWebView }
        )

        owner.zoomInCurrentTab()

        XCTAssertEqual(host.activePresentationWebView.pageZoom, 1.15, accuracy: 0.001)
        XCTAssertEqual(canonicalWebView.pageZoom, 1, accuracy: 0.001)
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
        activePresentationWebView: @escaping @MainActor (BrowserWindowState) -> WKWebView? = { _ in nil },
        tab: @escaping @MainActor (UUID) -> Tab? = { _ in nil },
        windowStateContainingTab: @escaping @MainActor (Tab) -> BrowserWindowState? = { _ in nil },
        webView: @escaping @MainActor (UUID, UUID) -> WKWebView? = { _, _ in nil },
        sizeOverride: @escaping @MainActor (URL, UUID?) -> Double = { _, _ in 1.0 },
        incrementZoomStateRevision: @escaping @MainActor () -> Void = { /* No-op. */ },
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)? = { nil }
    ) -> BrowserZoomCommandOwner {
        BrowserZoomCommandOwner(
            activeWindow: activeWindow,
            activePageTab: activePageTab,
            activePresentationWebView: activePresentationWebView,
            tab: tab,
            windowStateContainingTab: windowStateContainingTab,
            webView: webView,
            zoomManager: { zoomManager },
            sizeOverride: sizeOverride,
            incrementZoomStateRevision: incrementZoomStateRevision,
            notifications: notifications
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
