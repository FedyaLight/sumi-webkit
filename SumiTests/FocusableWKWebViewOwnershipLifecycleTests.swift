import AppKit
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class FocusableWKWebViewOwnershipLifecycleTests: XCTestCase {
    func testTrackedAssignmentPreservesExactTabAndCleanupIsolatesSiblingClone() throws {
        let repository = WebViewSessionRepository()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/owned")),
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let graph = makeTestWebViewRuntimeGraph(
            webViewSessions: repository,
            resolveRuntimeTab: { tabID in
                tabID == tab.id ? tab : nil
            }
        )
        let retiredWindowID = UUID()
        let siblingWindowID = UUID()
        let retired = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        let sibling = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        retired.owningTab = tab
        sibling.owningTab = tab

        graph.trackedWebViewAdmission.attemptAssignment(
            retired,
            to: tab,
            in: retiredWindowID,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )
        graph.trackedWebViewAdmission.attemptAssignment(
            sibling,
            to: tab,
            in: siblingWindowID,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )

        XCTAssertIdentical(retired.owningTab, tab)
        XCTAssertIdentical(sibling.owningTab, tab)
        XCTAssertEqual(
            graph.ownershipQuery.trackedOwner(containing: retired),
            TrackedWebViewOwner(tabID: tab.id, windowID: retiredWindowID)
        )
        XCTAssertEqual(
            graph.ownershipQuery.trackedOwner(containing: sibling),
            TrackedWebViewOwner(tabID: tab.id, windowID: siblingWindowID)
        )

        try seedInteractionState(
            on: retired,
            href: "https://example.com/retired-target",
            modifiers: .command,
            selectedText: "retired"
        )
        try seedInteractionState(
            on: sibling,
            href: "https://example.com/sibling-target",
            modifiers: .option,
            selectedText: "sibling"
        )

        graph.lifecycleService.cleanupTrackedWebView(
            retired,
            owner: TrackedWebViewOwner(
                tabID: tab.id,
                windowID: retiredWindowID
            )
        )

        XCTAssertNil(graph.ownershipQuery.trackedOwner(containing: retired))
        XCTAssertNil(retired.owningTab)
        XCTAssertEqual(
            retired.gestures.resolvedModifierFlags(actionFlags: []),
            []
        )
        XCTAssertNil(retired.hoveredLink.href)
        XCTAssertNil(retired.contextMenu.recentTarget())
        XCTAssertFalse(
            retired.popupUserActivation.activationState(
                webKitUserInitiated: false
            ).isUserActivated
        )

        XCTAssertEqual(
            graph.ownershipQuery.trackedOwner(containing: sibling),
            TrackedWebViewOwner(tabID: tab.id, windowID: siblingWindowID)
        )
        XCTAssertIdentical(sibling.owningTab, tab)
        XCTAssertEqual(
            sibling.gestures.resolvedModifierFlags(actionFlags: []),
            .option
        )
        XCTAssertEqual(
            sibling.hoveredLink.href,
            "https://example.com/sibling-target"
        )
        XCTAssertEqual(
            sibling.contextMenu.recentTarget()?.selectedText,
            "sibling"
        )
        XCTAssertTrue(
            sibling.popupUserActivation.activationState(
                webKitUserInitiated: false
            ).isUserActivated
        )
    }

    func testReusedFocusableWebViewRebindsStalePhysicalOwner() throws {
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/reused")),
            loadsCachedFaviconOnInit: false
        )
        let staleTab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/previous-owner")),
            loadsCachedFaviconOnInit: false
        )
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        webView.owningTab = staleTab
        let preparation = TabOwnedWebViewPreparationOwner(
            dependencies: .live(tab: tab)
        )

        preparation.prepareReusedOrExternallyCreatedWebView(webView)

        XCTAssertIdentical(webView.owningTab, tab)
    }

    private func seedInteractionState(
        on webView: FocusableWKWebView,
        href: String,
        modifiers: NSEvent.ModifierFlags,
        selectedText: String
    ) throws {
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 20, y: 30),
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 0
            )
        )
        webView.recordUserGesture(event, kind: .primaryMouseDown)
        webView.hoveredLink.update(href)
        webView.contextMenu.record(
            SumiWebPageContextMenuTargetSnapshot(
                kind: .link,
                selectedText: selectedText
            )
        )
    }
}
