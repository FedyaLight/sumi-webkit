import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewHiddenCloneEvictionOwnerTests: XCTestCase {
    func testRejectedCleanupDoesNotRefreshPrimaryWebView() {
        let tab = Tab(
            url: URL(string: "about:blank")!,
            loadsCachedFaviconOnInit: false
        )
        let hiddenWebView = WKWebView()
        let siblingWebView = WKWebView()
        let windowID = UUID()
        let owner = TrackedWebViewOwner(
            tabID: tab.id,
            windowID: windowID
        )
        var refreshCount = 0

        let didEvict = WebViewHiddenCloneEvictionOwner().evictHiddenWebViews(
            in: windowID,
            visibleTabIDs: [],
            entries: [(owner, hiddenWebView)],
            runtime: .init(
                tabForID: { _ in tab },
                liveWebViews: { _ in [hiddenWebView, siblingWebView] },
                globallyVisibleTabIDs: { [tab.id] },
                isWebViewProtectedFromCompositorMutation: { _ in false },
                enqueueDeferredProtectedCommand: { _, _, _ in false },
                cleanupUnprotectedTrackedWebView: { _, _, _ in false },
                refreshPrimaryTrackedWebView: { _ in refreshCount += 1 }
            )
        )

        XCTAssertFalse(didEvict)
        XCTAssertEqual(refreshCount, 0)
    }
}
