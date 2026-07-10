import WebKit
import XCTest
import SumiWebRuntime

@testable import Sumi

@MainActor
final class WebViewScopedCleanupValidationTests: XCTestCase {
    func testRejectsTrackedWebViewEvenWhenTrackedForSameTab() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let tab = makeTab()
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)

        XCTAssertFalse(validator.canCleanUpDetachedWebView(
            with: ObjectIdentifier(webView),
            tabID: tab.id,
            context: makeContext(
                webView: webView,
                residence: .window(.init(tabID: tab.id, windowID: UUID()))
            )
        ))
    }

    func testAllowsCurrentUntrackedWebViewOwnedByTargetTab() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let tab = makeTab()
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)

        XCTAssertTrue(validator.canCleanUpDetachedWebView(
            with: ObjectIdentifier(webView),
            tabID: tab.id,
            context: makeContext(
                webView: webView,
                residence: .untracked(tabID: tab.id)
            )
        ))
    }

    func testRejectsOwnerlessWebViewAfterTargetTabClearsOwnership() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let tab = makeTab()
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        tab.clearCurrentWebViewOwnership()

        XCTAssertFalse(validator.canCleanUpDetachedWebView(
            with: ObjectIdentifier(webView),
            tabID: tab.id,
            context: makeContext(webView: webView)
        ))
    }

    func testRejectsUntrackedWebViewOwnedByAnotherTab() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let targetTab = makeTab()
        let otherTab = makeTab(urlString: "https://other.example")
        let webView = WKWebView()
        otherTab.replaceUntrackedWebView(webView)

        XCTAssertFalse(validator.canCleanUpDetachedWebView(
            with: ObjectIdentifier(webView),
            tabID: targetTab.id,
            context: makeContext(
                webView: webView,
                residence: .untracked(tabID: otherTab.id)
            )
        ))
    }

    func testRejectsDeadWebView() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let tab = makeTab()
        let webView = WKWebView()

        XCTAssertFalse(validator.canCleanUpDetachedWebView(
            with: ObjectIdentifier(webView),
            tabID: tab.id,
            context: makeContext(webView: nil)
        ))
    }

    func testFallbackCleanupRequiresExactPendingCleanupLease() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let webView = WKWebView()
        let lease = WebViewPendingCleanupLease(id: UUID(), tabID: UUID())
        let context = makeContext(
            webView: webView,
            residence: .pendingCleanup(lease)
        )

        XCTAssertTrue(validator.canPerformFallbackCleanup(
            with: ObjectIdentifier(webView),
            lease: lease,
            context: context
        ))
        XCTAssertFalse(validator.canPerformFallbackCleanup(
            with: ObjectIdentifier(webView),
            lease: .init(id: UUID(), tabID: lease.tabID),
            context: context
        ))
    }

    private func makeContext(
        webView: WKWebView?,
        residence: WebViewResidence? = nil
    ) -> WebViewTabScopedCleanupValidationOwner.Context {
        let webViewID = webView.map(ObjectIdentifier.init)
        return WebViewTabScopedCleanupValidationOwner.Context(
            resolveWebView: { candidateID in
                guard let webViewID, candidateID == webViewID else { return nil }
                return webView
            },
            residence: { candidateWebView in
                guard candidateWebView === webView else { return nil }
                return residence
            }
        )
    }

    private func makeTab(urlString: String = "https://example.com") -> Tab {
        Tab(
            url: URL(string: urlString)!,
            loadsCachedFaviconOnInit: false
        )
    }
}
