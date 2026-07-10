import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewCoordinatorTrackedWebViewsTests: XCTestCase {
    func testTrackedLiveWebViewsExcludesUntrackedTabWebView() throws {
        let coordinator = WebViewCoordinator()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            webViewSessions: coordinator.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let untrackedWebView = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(untrackedWebView)

        XCTAssertTrue(coordinator.ownershipQuery.trackedLiveWebViews(for: tab).isEmpty)
    }

    func testSuspensionLiveWebViewsIncludesCurrentAndParkedUntrackedWebViews() throws {
        let coordinator = WebViewCoordinator()
        let parkedWebView = WKWebView(frame: .zero)
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            existingWebView: parkedWebView,
            webViewSessions: coordinator.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let currentWebView = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(currentWebView)

        let liveWebViews = coordinator.ownershipQuery.suspensionLiveWebViews(for: tab)

        XCTAssertEqual(liveWebViews.count, 2)
        XCTAssertTrue(liveWebViews.contains { $0 === currentWebView })
        XCTAssertTrue(liveWebViews.contains { $0 === parkedWebView })
        XCTAssertTrue(coordinator.ownershipQuery.trackedLiveWebViews(for: tab).isEmpty)
    }

    func testTrackedLiveWebViewsReturnsOnlyCoordinatorRegisteredWebViews() throws {
        let coordinator = WebViewCoordinator()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            webViewSessions: coordinator.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(WKWebView(frame: .zero))
        let windowId = UUID()
        let trackedWebView = WKWebView(frame: .zero)

        coordinator.ownershipService.registerTrackedWebView(
            trackedWebView,
            for: tab,
            in: windowId
        )

        XCTAssertEqual(coordinator.ownershipQuery.trackedLiveWebViews(for: tab).count, 1)
        XCTAssertIdentical(
            coordinator.ownershipQuery.trackedLiveWebViews(for: tab).first,
            trackedWebView
        )
    }

    func testEnsureUntrackedOwnedWebViewReturnsExistingLiveWebView() throws {
        let coordinator = WebViewCoordinator()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/ensure-untracked-reuse")),
            webViewSessions: coordinator.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let existing = FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        existing.owningTab = tab
        tab.replaceUntrackedWebView(existing)

        let first = try XCTUnwrap(coordinator.ownershipService.ensureUntracked(for: tab))
        let second = try XCTUnwrap(coordinator.ownershipService.ensureUntracked(for: tab))

        XCTAssertIdentical(first, existing)
        XCTAssertIdentical(first, second)
        XCTAssertNil(tab.resolvedPrimaryWindowId())
        XCTAssertIdentical(coordinator.ownershipQuery.untrackedOwnedWebView(for: tab), existing)
    }
}
