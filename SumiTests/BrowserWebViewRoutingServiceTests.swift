import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserWebViewRoutingServiceTests: XCTestCase {
    func testMissingTabDoesNotResolveCoordinatorForTabBackedOperations() throws {
        let coordinator = RecordingWebViewCoordinator()
        var coordinatorReadCount = 0
        let service = BrowserWebViewRoutingService(
            tabLookup: { _ in nil },
            coordinatorProvider: {
                coordinatorReadCount += 1
                return coordinator
            }
        )
        let tabId = UUID()

        service.syncTabAcrossWindows(tabId)
        service.reloadTabAcrossWindows(tabId)
        service.reloadTab(tabId, in: UUID())

        XCTAssertEqual(coordinatorReadCount, 0)
        XCTAssertTrue(coordinator.syncCalls.isEmpty)
        XCTAssertTrue(coordinator.reloadCalls.isEmpty)
        XCTAssertTrue(coordinator.windowReloadCalls.isEmpty)
    }

    func testCoordinatorCallsStillDelegateWhenCoordinatorIsPresent() throws {
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            loadsCachedFaviconOnInit: false
        )
        let coordinator = RecordingWebViewCoordinator()
        let expectedWebView = WKWebView()
        let originatingWebView = WKWebView()
        coordinator.webViewToReturn = expectedWebView
        let windowId = UUID()
        let reloadWindowId = UUID()
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            coordinatorProvider: { coordinator }
        )

        let webView = service.webView(for: tab.id, in: windowId)
        service.syncTabAcrossWindows(tab.id, originatingWebView: originatingWebView)
        service.reloadTabAcrossWindows(tab.id)
        service.reloadTab(tab.id, in: reloadWindowId)
        service.setMuteState(true, for: tab.id)

        XCTAssertIdentical(webView, expectedWebView)
        XCTAssertEqual(coordinator.webViewRequests.count, 1)
        XCTAssertEqual(coordinator.webViewRequests.first?.tabId, tab.id)
        XCTAssertEqual(coordinator.webViewRequests.first?.windowId, windowId)

        let syncCall = try XCTUnwrap(coordinator.syncCalls.first)
        XCTAssertIdentical(syncCall.tab, tab)
        XCTAssertEqual(syncCall.url, tab.url)
        XCTAssertTrue(syncCall.originatingWebView === originatingWebView)

        XCTAssertEqual(coordinator.reloadCalls.count, 1)
        XCTAssertIdentical(coordinator.reloadCalls.first, tab)
        let windowReload = try XCTUnwrap(coordinator.windowReloadCalls.first)
        XCTAssertIdentical(windowReload.tab, tab)
        XCTAssertEqual(windowReload.windowId, reloadWindowId)
        XCTAssertEqual(coordinator.muteCalls.count, 1)
        XCTAssertEqual(coordinator.muteCalls.first?.muted, true)
        XCTAssertEqual(coordinator.muteCalls.first?.tabId, tab.id)
    }

    func testWindowOwnedWebViewPrefersCoordinatorTrackedWebView() throws {
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            loadsCachedFaviconOnInit: false
        )
        let tabWebView = WKWebView()
        let trackedWebView = WKWebView()
        tab.replaceUntrackedWebView(tabWebView)
        let coordinator = RecordingWebViewCoordinator()
        coordinator.webViewToReturn = trackedWebView
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            coordinatorProvider: { coordinator }
        )

        XCTAssertIdentical(service.windowOwnedWebView(for: tab, in: UUID()), trackedWebView)
    }

    func testWindowOwnedWebViewDoesNotReturnUntrackedCurrentWebView() throws {
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            loadsCachedFaviconOnInit: false
        )
        let tabWebView = WKWebView()
        tab.replaceUntrackedWebView(tabWebView)
        let coordinator = RecordingWebViewCoordinator()
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            coordinatorProvider: { coordinator }
        )

        XCTAssertNil(service.windowOwnedWebView(for: tab, in: UUID()))
    }

    func testWindowOwnedWebViewDoesNotReturnAssignedWebViewForDifferentWindow() throws {
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(WKWebView())
        tab.primaryWindowId = UUID()
        let coordinator = RecordingWebViewCoordinator()
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            coordinatorProvider: { coordinator }
        )

        XCTAssertNil(service.windowOwnedWebView(for: tab, in: UUID()))
    }
}

private final class RecordingWebViewCoordinator: WebViewCoordinator {
    struct WebViewRequest {
        let tabId: UUID
        let windowId: UUID
    }

    struct SyncCall {
        let tab: Tab
        let url: URL
        let originatingWebView: WKWebView?
    }

    struct MuteCall {
        let muted: Bool
        let tabId: UUID
    }

    struct WindowReloadCall {
        let tab: Tab
        let windowId: UUID
    }

    var webViewToReturn: WKWebView?
    private(set) var webViewRequests: [WebViewRequest] = []
    private(set) var syncCalls: [SyncCall] = []
    private(set) var reloadCalls: [Tab] = []
    private(set) var windowReloadCalls: [WindowReloadCall] = []
    private(set) var muteCalls: [MuteCall] = []

    override func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        webViewRequests.append(WebViewRequest(tabId: tabId, windowId: windowId))
        return webViewToReturn
    }

    override func syncTab(_ tab: Tab, to url: URL, originatingWebView: WKWebView?) {
        syncCalls.append(
            SyncCall(
                tab: tab,
                url: url,
                originatingWebView: originatingWebView
            )
        )
    }

    override func reloadTab(_ tab: Tab) {
        reloadCalls.append(tab)
    }

    override func reloadTab(_ tab: Tab, in windowId: UUID) -> Bool {
        windowReloadCalls.append(WindowReloadCall(tab: tab, windowId: windowId))
        return true
    }

    override func setMuteState(_ muted: Bool, for tabId: UUID) {
        muteCalls.append(MuteCall(muted: muted, tabId: tabId))
    }
}
