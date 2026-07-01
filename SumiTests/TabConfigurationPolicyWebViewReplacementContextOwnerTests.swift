import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewReplacementContextOwnerTests: XCTestCase {
    func testMakeContextReflectsUntrackedTabWebViewOwnership() {
        let owner = TabWebViewReplacementContextOwner()
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
        let owner = TabWebViewReplacementContextOwner()
        let tab = Tab(url: URL(string: "https://example.com/replacement-runtime")!)
        let webView = WKWebView()
        let windowId = UUID()
        var setTrackedCalls: [TrackedWebViewSetCall] = []
        var removeTrackedTabIds: [UUID] = []
        var refreshedWindowIds: [UUID] = []

        tab.webViewReplacementRuntime = TabWebViewReplacementRuntime(
            trackedWindowIdContainingWebView: { candidate in
                XCTAssertIdentical(candidate, webView)
                return windowId
            },
            hasTrackedWebViews: { tabId in
                XCTAssertEqual(tabId, tab.id)
                return true
            },
            setTrackedWebView: { replacement, tabId, resolvedWindowId in
                setTrackedCalls.append(TrackedWebViewSetCall(
                    webViewIdentifier: ObjectIdentifier(replacement),
                    tabId: tabId,
                    windowId: resolvedWindowId
                ))
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
        XCTAssertEqual(setTrackedCalls.map(\.webViewIdentifier), [ObjectIdentifier(webView)])
        XCTAssertEqual(setTrackedCalls.map(\.tabId), [tab.id])
        XCTAssertEqual(setTrackedCalls.map(\.windowId), [windowId])
        XCTAssertTrue(context.removeTrackedWebViews())
        XCTAssertEqual(removeTrackedTabIds, [tab.id])
        context.refreshWindowAfterWebViewReplacement(windowId)
        XCTAssertEqual(refreshedWindowIds, [windowId])
    }
}

private struct TrackedWebViewSetCall {
    let webViewIdentifier: ObjectIdentifier
    let tabId: UUID
    let windowId: UUID
}
