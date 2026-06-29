import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserWebViewRoutingServiceTests: XCTestCase {
    func testNilCoordinatorReturnsNilAndDropsRoutingOperations() throws {
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            loadsCachedFaviconOnInit: false
        )
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            coordinatorLookup: { nil }
        )

        XCTAssertNil(service.webView(for: tab.id, in: UUID()))
        service.syncTabAcrossWindows(tab.id)
        service.reloadTabAcrossWindows(tab.id)
        service.setMuteState(true, for: tab.id)
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
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            coordinatorLookup: { coordinator }
        )

        let webView = service.webView(for: tab.id, in: windowId)
        service.syncTabAcrossWindows(tab.id, originatingWebView: originatingWebView)
        service.reloadTabAcrossWindows(tab.id)
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
        XCTAssertEqual(coordinator.muteCalls.count, 1)
        XCTAssertEqual(coordinator.muteCalls.first?.muted, true)
        XCTAssertEqual(coordinator.muteCalls.first?.tabId, tab.id)
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

    var webViewToReturn: WKWebView?
    private(set) var webViewRequests: [WebViewRequest] = []
    private(set) var syncCalls: [SyncCall] = []
    private(set) var reloadCalls: [Tab] = []
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

    override func setMuteState(_ muted: Bool, for tabId: UUID) {
        muteCalls.append(MuteCall(muted: muted, tabId: tabId))
    }
}
