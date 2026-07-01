import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewScopedCleanupValidationTests: XCTestCase {
    func testRejectsTrackedWebViewEvenWhenTrackedForSameTab() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let tab = makeTab()
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)

        XCTAssertFalse(validator.canCleanUpTabScopedWebView(
            with: ObjectIdentifier(webView),
            tabID: tab.id,
            context: makeContext(
                webView: webView,
                trackedOwner: TrackedWebViewOwner(tabID: tab.id, windowID: UUID()),
                resolvedTab: tab,
                allTabs: [tab]
            )
        ))
    }

    func testAllowsCurrentUntrackedWebViewOwnedByTargetTab() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let tab = makeTab()
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)

        XCTAssertTrue(validator.canCleanUpTabScopedWebView(
            with: ObjectIdentifier(webView),
            tabID: tab.id,
            context: makeContext(webView: webView, resolvedTab: tab, allTabs: [tab])
        ))
    }

    func testAllowsUnownedWebViewAfterTargetTabClearsOwnership() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let tab = makeTab()
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        tab.clearCurrentWebViewOwnership()

        XCTAssertTrue(validator.canCleanUpTabScopedWebView(
            with: ObjectIdentifier(webView),
            tabID: tab.id,
            context: makeContext(webView: webView, resolvedTab: tab, allTabs: [tab])
        ))
    }

    func testRejectsUntrackedWebViewOwnedByAnotherTab() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let targetTab = makeTab()
        let otherTab = makeTab(urlString: "https://other.example")
        let webView = WKWebView()
        otherTab.replaceUntrackedWebView(webView)

        XCTAssertFalse(validator.canCleanUpTabScopedWebView(
            with: ObjectIdentifier(webView),
            tabID: targetTab.id,
            context: makeContext(
                webView: webView,
                resolvedTab: targetTab,
                allTabs: [targetTab, otherTab]
            )
        ))
    }

    func testRejectsDeadWebView() {
        let validator = WebViewTabScopedCleanupValidationOwner()
        let tab = makeTab()
        let webView = WKWebView()

        XCTAssertFalse(validator.canCleanUpTabScopedWebView(
            with: ObjectIdentifier(webView),
            tabID: tab.id,
            context: makeContext(webView: nil, resolvedTab: tab, allTabs: [tab])
        ))
    }

    private func makeContext(
        webView: WKWebView?,
        trackedOwner: TrackedWebViewOwner? = nil,
        resolvedTab: Tab?,
        allTabs: [Tab]
    ) -> WebViewTabScopedCleanupValidationOwner.Context {
        let webViewID = webView.map(ObjectIdentifier.init)
        return WebViewTabScopedCleanupValidationOwner.Context(
            trackedOwner: { candidateID in
                guard let webViewID, candidateID == webViewID else { return nil }
                return trackedOwner
            },
            resolveWebView: { candidateID in
                guard let webViewID, candidateID == webViewID else { return nil }
                return webView
            },
            resolveTab: { candidateTabID in
                resolvedTab?.id == candidateTabID ? resolvedTab : nil
            },
            allTabs: { allTabs }
        )
    }

    private func makeTab(urlString: String = "https://example.com") -> Tab {
        Tab(
            url: URL(string: urlString)!,
            loadsCachedFaviconOnInit: false
        )
    }
}
