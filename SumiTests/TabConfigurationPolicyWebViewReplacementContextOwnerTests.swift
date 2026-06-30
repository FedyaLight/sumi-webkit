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

    func testMakeContextUsesInjectedReplacementRuntimeWithoutBrowserManager() {
        let owner = TabConfigurationPolicyWebViewReplacementContextOwner()
        let tab = Tab(url: URL(string: "https://example.com/replacement-runtime")!)
        let webView = WKWebView()
        let windowId = UUID()
        var setTrackedCalls: [(ObjectIdentifier, UUID, UUID)] = []
        var removeTrackedTabIds: [UUID] = []
        var refreshedWindowIds: [UUID] = []

        tab.configurationPolicyWebViewReplacementRuntime = TabConfigurationPolicyWebViewReplacementRuntime(
            trackedWindowIdContainingWebView: { candidate in
                XCTAssertIdentical(candidate, webView)
                return windowId
            },
            hasTrackedWebViews: { tabId in
                XCTAssertEqual(tabId, tab.id)
                return true
            },
            setTrackedWebView: { replacement, tabId, resolvedWindowId in
                setTrackedCalls.append((ObjectIdentifier(replacement), tabId, resolvedWindowId))
            },
            removeTrackedWebViews: { runtimeTab in
                removeTrackedTabIds.append(runtimeTab.id)
                return true
            },
            refreshWindowAfterWebViewReplacement: { resolvedWindowId in
                refreshedWindowIds.append(resolvedWindowId)
            }
        )

        let context = owner.makeContext(for: tab)

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(context.trackedWindowIdContainingWebView(webView), windowId)
        XCTAssertTrue(context.hasTrackedWebViews(tab.id))
        context.setTrackedWebView(webView, tab.id, windowId)
        XCTAssertEqual(setTrackedCalls.map(\.0), [ObjectIdentifier(webView)])
        XCTAssertEqual(setTrackedCalls.map(\.1), [tab.id])
        XCTAssertEqual(setTrackedCalls.map(\.2), [windowId])
        XCTAssertTrue(context.removeTrackedWebViews())
        XCTAssertEqual(removeTrackedTabIds, [tab.id])
        context.refreshWindowAfterWebViewReplacement(windowId)
        XCTAssertEqual(refreshedWindowIds, [windowId])
    }
}
