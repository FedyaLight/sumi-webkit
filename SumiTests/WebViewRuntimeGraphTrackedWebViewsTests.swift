import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewRuntimeGraphTrackedWebViewsTests: XCTestCase {
    func testTrackedLiveWebViewsExcludesUntrackedTabWebView() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let untrackedWebView = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(untrackedWebView)

        XCTAssertTrue(graph.ownershipQuery.trackedLiveWebViews(for: tab).isEmpty)
    }

    func testSuspensionLiveWebViewsIncludesCurrentAndParkedUntrackedWebViews() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let parkedWebView = WKWebView(frame: .zero)
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            existingWebView: parkedWebView,
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let currentWebView = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(currentWebView)

        let liveWebViews = graph.ownershipQuery.suspensionLiveWebViews(for: tab)

        XCTAssertEqual(liveWebViews.count, 2)
        XCTAssertTrue(liveWebViews.contains { $0 === currentWebView })
        XCTAssertTrue(liveWebViews.contains { $0 === parkedWebView })
        XCTAssertTrue(graph.ownershipQuery.trackedLiveWebViews(for: tab).isEmpty)
    }

    func testTrackedLiveWebViewsReturnsOnlyGraphRegisteredWebViews() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(WKWebView(frame: .zero))
        let windowId = UUID()
        let trackedWebView = WKWebView(frame: .zero)

        graph.ownershipService.registerTrackedWebView(
            trackedWebView,
            for: tab,
            in: windowId
        )

        XCTAssertEqual(graph.ownershipQuery.trackedLiveWebViews(for: tab).count, 1)
        XCTAssertIdentical(
            graph.ownershipQuery.trackedLiveWebViews(for: tab).first,
            trackedWebView
        )
    }

    func testEnsureUntrackedOwnedWebViewReturnsExistingLiveWebView() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/ensure-untracked-reuse")),
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let existing = FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        existing.owningTab = tab
        tab.replaceUntrackedWebView(existing)

        let first = try XCTUnwrap(graph.ownershipService.ensureUntracked(for: tab))
        let second = try XCTUnwrap(graph.ownershipService.ensureUntracked(for: tab))

        XCTAssertIdentical(first, existing)
        XCTAssertIdentical(first, second)
        XCTAssertNil(tab.resolvedPrimaryWindowId())
        XCTAssertIdentical(graph.ownershipQuery.untrackedOwnedWebView(for: tab), existing)
    }
}
