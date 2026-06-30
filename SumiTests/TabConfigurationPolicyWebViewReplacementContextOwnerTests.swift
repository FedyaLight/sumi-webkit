import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabConfigurationPolicyWebViewReplacementContextOwnerTests: XCTestCase {
    func testMakeContextReflectsUntrackedTabWebViewOwnership() {
        let owner = TabConfigurationPolicyWebViewReplacementContextOwner()
        let tab = Tab(url: URL(string: "https://example.com/replacement-context")!)
        let existingWebView = WKWebView()
        let replacementWebView = WKWebView()
        let windowId = UUID()

        tab._webView = existingWebView

        let context = owner.makeContext(for: tab)

        XCTAssertEqual(context.tabId, tab.id)
        XCTAssertIdentical(context.existingWebView(), existingWebView)
        XCTAssertNil(context.trackedWindowIdContainingWebView(existingWebView))
        XCTAssertFalse(context.hasTrackedWebViews(tab.id))
        XCTAssertFalse(context.removeTrackedWebViews())

        context.replaceUntrackedWebView(replacementWebView)

        XCTAssertIdentical(tab.existingWebView, replacementWebView)

        context.assignWebViewToWindow(replacementWebView, windowId)

        XCTAssertIdentical(tab.assignedWebView, replacementWebView)
        XCTAssertEqual(tab.primaryWindowId, windowId)

        context.clearCurrentWebViewOwnership()

        XCTAssertNil(tab.existingWebView)
        XCTAssertNil(tab.primaryWindowId)
    }
}
