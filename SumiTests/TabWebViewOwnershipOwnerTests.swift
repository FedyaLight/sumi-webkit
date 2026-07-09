import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewOwnershipOwnerTests: XCTestCase {
    func testAssignPrimaryWebViewTracksWindowAndAssignedWebView() {
        let owner = TabWebViewOwnershipOwner(tabId: UUID())
        let webView = WKWebView()
        let windowId = UUID()

        owner.assignPrimaryWebView(webView, windowId: windowId)

        XCTAssertIdentical(owner.localSession.currentWebView, webView)
        XCTAssertIdentical(owner.localSession.primaryWebView, webView)
        XCTAssertEqual(owner.localSession.primaryWindowId, windowId)
        XCTAssertFalse(owner.isUnloaded)
    }

    func testReplaceUntrackedWebViewClearsPrimaryWindowOwnership() {
        let owner = TabWebViewOwnershipOwner(tabId: UUID())
        owner.assignPrimaryWebView(WKWebView(), windowId: UUID())

        let replacement = WKWebView()
        owner.replaceUntrackedWebView(replacement)

        XCTAssertIdentical(owner.localSession.currentWebView, replacement)
        XCTAssertNil(owner.localSession.primaryWebView)
        XCTAssertNil(owner.localSession.primaryWindowId)
    }

    func testClearCurrentWebViewOwnershipPreservesParkedExistingWebView() {
        let owner = TabWebViewOwnershipOwner(tabId: UUID())
        let parked = WKWebView()
        owner.parkExistingWebView(parked)
        owner.assignPrimaryWebView(WKWebView(), windowId: UUID())

        owner.clearCurrentWebViewOwnership()

        XCTAssertNil(owner.localSession.currentWebView)
        XCTAssertNil(owner.localSession.primaryWebView)
        XCTAssertNil(owner.localSession.primaryWindowId)
        XCTAssertIdentical(owner.localSession.parkedWebView, parked)
        XCTAssertTrue(owner.isUnloaded)
    }

    func testClearAllWebViewOwnershipClearsCurrentParkedAndWindowSlots() {
        let owner = TabWebViewOwnershipOwner(tabId: UUID())
        owner.parkExistingWebView(WKWebView())
        owner.assignPrimaryWebView(WKWebView(), windowId: UUID())

        owner.clearAllWebViewOwnership()

        XCTAssertNil(owner.localSession.currentWebView)
        XCTAssertNil(owner.localSession.parkedWebView)
        XCTAssertNil(owner.localSession.primaryWebView)
        XCTAssertNil(owner.localSession.primaryWindowId)
        XCTAssertTrue(owner.isUnloaded)
    }

    func testClearCurrentWebViewOwnershipIfIdenticalDoesNotClearReplacement() {
        let owner = TabWebViewOwnershipOwner(tabId: UUID())
        let current = WKWebView()
        let other = WKWebView()
        let windowId = UUID()
        owner.assignPrimaryWebView(current, windowId: windowId)

        XCTAssertFalse(owner.clearCurrentWebViewOwnershipIfIdentical(to: other))
        XCTAssertIdentical(owner.localSession.currentWebView, current)
        XCTAssertEqual(owner.localSession.primaryWindowId, windowId)

        XCTAssertTrue(owner.clearCurrentWebViewOwnershipIfIdentical(to: current))
        XCTAssertNil(owner.localSession.currentWebView)
        XCTAssertNil(owner.localSession.primaryWindowId)
    }

    func testTabRuntimeQueriesExposeCurrentAndParkedWebViews() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let current = WKWebView()
        let parked = WKWebView()

        tab.replaceUntrackedWebView(current)
        tab.parkExistingWebView(parked)

        XCTAssertIdentical(tab.resolvedCurrentWebView(), current)
        XCTAssertTrue(tab.hasCurrentWebView)
        XCTAssertIdentical(tab.resolvedParkedWebView(), parked)
        XCTAssertTrue(tab.hasParkedWebView)
        XCTAssertTrue(tab.currentWebViewIsIdentical(to: current))
        XCTAssertFalse(tab.currentWebViewIsIdentical(to: parked))
    }
}
