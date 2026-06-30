import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewOwnershipOwnerTests: XCTestCase {
    func testAssignPrimaryWebViewTracksWindowAndAssignedWebView() {
        let owner = TabWebViewOwnershipOwner()
        let webView = WKWebView()
        let windowId = UUID()

        owner.assignPrimaryWebView(webView, windowId: windowId)

        XCTAssertTrue(owner.webView === webView)
        XCTAssertTrue(owner.assignedWebView === webView)
        XCTAssertEqual(owner.primaryWindowId, windowId)
        XCTAssertFalse(owner.isUnloaded)
    }

    func testReplaceUntrackedWebViewClearsPrimaryWindowOwnership() {
        let owner = TabWebViewOwnershipOwner()
        owner.assignPrimaryWebView(WKWebView(), windowId: UUID())

        let replacement = WKWebView()
        owner.replaceUntrackedWebView(replacement)

        XCTAssertTrue(owner.webView === replacement)
        XCTAssertNil(owner.assignedWebView)
        XCTAssertNil(owner.primaryWindowId)
    }

    func testClearCurrentWebViewOwnershipPreservesParkedExistingWebView() {
        let owner = TabWebViewOwnershipOwner()
        let parked = WKWebView()
        owner.parkExistingWebView(parked)
        owner.assignPrimaryWebView(WKWebView(), windowId: UUID())

        owner.clearCurrentWebViewOwnership()

        XCTAssertNil(owner.webView)
        XCTAssertNil(owner.assignedWebView)
        XCTAssertNil(owner.primaryWindowId)
        XCTAssertTrue(owner.existingWebView === parked)
        XCTAssertTrue(owner.isUnloaded)
    }

    func testClearAllWebViewOwnershipClearsCurrentParkedAndWindowSlots() {
        let owner = TabWebViewOwnershipOwner()
        owner.parkExistingWebView(WKWebView())
        owner.assignPrimaryWebView(WKWebView(), windowId: UUID())

        owner.clearAllWebViewOwnership()

        XCTAssertNil(owner.webView)
        XCTAssertNil(owner.existingWebView)
        XCTAssertNil(owner.assignedWebView)
        XCTAssertNil(owner.primaryWindowId)
        XCTAssertTrue(owner.isUnloaded)
    }

    func testClearCurrentWebViewOwnershipIfIdenticalDoesNotClearReplacement() {
        let owner = TabWebViewOwnershipOwner()
        let current = WKWebView()
        let other = WKWebView()
        let windowId = UUID()
        owner.assignPrimaryWebView(current, windowId: windowId)

        XCTAssertFalse(owner.clearCurrentWebViewOwnershipIfIdentical(to: other))
        XCTAssertTrue(owner.webView === current)
        XCTAssertEqual(owner.primaryWindowId, windowId)

        XCTAssertTrue(owner.clearCurrentWebViewOwnershipIfIdentical(to: current))
        XCTAssertNil(owner.webView)
        XCTAssertNil(owner.primaryWindowId)
    }

    func testTabRuntimeQueriesExposeCurrentAndParkedWebViews() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let current = WKWebView()
        let parked = WKWebView()

        tab.replaceUntrackedWebView(current)
        tab.parkExistingWebView(parked)

        XCTAssertIdentical(tab.currentWebView, current)
        XCTAssertTrue(tab.hasCurrentWebView)
        XCTAssertIdentical(tab.parkedWebView, parked)
        XCTAssertTrue(tab.hasParkedWebView)
        XCTAssertTrue(tab.currentWebViewIsIdentical(to: current))
        XCTAssertFalse(tab.currentWebViewIsIdentical(to: parked))
    }
}
