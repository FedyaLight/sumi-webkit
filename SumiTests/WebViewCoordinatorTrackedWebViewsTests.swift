import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewCoordinatorTrackedWebViewsTests: XCTestCase {
    func testTrackedLiveWebViewsExcludesUntrackedTabWebView() throws {
        let coordinator = WebViewCoordinator()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            loadsCachedFaviconOnInit: false
        )
        let untrackedWebView = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(untrackedWebView)

        XCTAssertTrue(coordinator.trackedLiveWebViews(for: tab).isEmpty)
    }

    func testTrackedLiveWebViewsReturnsOnlyCoordinatorRegisteredWebViews() throws {
        let coordinator = WebViewCoordinator()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(WKWebView(frame: .zero))
        let windowId = UUID()
        let trackedWebView = WKWebView(frame: .zero)

        coordinator.setWebView(trackedWebView, for: tab.id, in: windowId)

        XCTAssertEqual(coordinator.trackedLiveWebViews(for: tab).count, 1)
        XCTAssertIdentical(coordinator.trackedLiveWebViews(for: tab).first, trackedWebView)
    }
}
