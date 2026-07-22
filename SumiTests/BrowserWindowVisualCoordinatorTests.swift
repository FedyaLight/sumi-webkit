import AppKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowVisualCoordinatorTests: XCTestCase {
    func testRefreshCompositorDefersDuringTabBackForwardNavigationUntilFlush() async {
        let fixture = VisualFixture()
        fixture.tab.navigationRuntime.navigationTransactionOwner
            .pendingMainFrameNavigationKind = .backForward

        fixture.visuals.refreshCompositor(for: fixture.window)
        await drainMainQueue()

        XCTAssertEqual(fixture.window.compositorInvalidation.compositorVersion, 0)

        fixture.tab.navigationRuntime.navigationTransactionOwner
            .pendingMainFrameNavigationKind = nil
        fixture.visuals.flushWindowMutationsAfterHistorySwipe(in: fixture.window.id)
        await drainMainQueue()

        XCTAssertEqual(fixture.window.compositorInvalidation.compositorVersion, 1)
    }

    func testRefreshCompositorDefersDuringFrozenBackForwardNavigationUntilFlush() async {
        let fixture = VisualFixture()
        fixture.tab.navigationRuntime.navigationTransactionOwner
            .isFreezingNavDuringBackForwardGesture = true

        fixture.visuals.refreshCompositor(for: fixture.window)
        await drainMainQueue()

        XCTAssertEqual(fixture.window.compositorInvalidation.compositorVersion, 0)

        fixture.tab.navigationRuntime.navigationTransactionOwner
            .isFreezingNavDuringBackForwardGesture = false
        fixture.visuals.flushWindowMutationsAfterHistorySwipe(in: fixture.window.id)
        await drainMainQueue()

        XCTAssertEqual(fixture.window.compositorInvalidation.compositorVersion, 1)
    }

    func testSchedulePrepareVisibleWebViewsDefersDuringActiveHistorySwipe() async {
        let fixture = VisualFixture()
        let webView = fixture.beginHistorySwipe()
        let initialVersion = fixture.window.compositorInvalidation.compositorVersion

        fixture.visuals.schedulePrepareVisibleWebViews(for: fixture.window)
        await drainMainQueue()

        XCTAssertEqual(
            fixture.window.compositorInvalidation.compositorVersion,
            initialVersion
        )

        _ = fixture.browser.webViewRuntime.protectionRuntime.finishHistorySwipe(
            tabID: fixture.tab.id,
            webView: webView,
            currentURL: nil,
            currentHistoryItem: nil
        )
        fixture.visuals.flushWindowMutationsAfterHistorySwipe(in: fixture.window.id)
        await drainMainQueue()

        XCTAssertGreaterThan(
            fixture.window.compositorInvalidation.compositorVersion,
            initialVersion
        )
    }

    func testImmediateVisualHandoffReturnsFalseDuringActiveHistorySwipe() {
        let fixture = VisualFixture()
        let webView = fixture.beginHistorySwipe()
        defer {
            _ = fixture.browser.webViewRuntime.protectionRuntime.finishHistorySwipe(
                tabID: fixture.tab.id,
                webView: webView,
                currentURL: nil,
                currentHistoryItem: nil
            )
        }
        fixture.browser.webViewRuntime.compositorRuntime.registerContainer(
            NSView(),
            for: fixture.window.id,
            immediateVisualHandoffHandler: {
                XCTFail("Handoff should not run during an active history swipe")
                return true
            }
        )

        XCTAssertFalse(
            fixture.visuals.performImmediateVisualHandoffIfPossible(
                in: fixture.window
            )
        )
    }

    func testImmediateVisualHandoffUsesExactCompositorRegistration() {
        let fixture = VisualFixture()
        var handoffCount = 0
        let container = NSView()
        fixture.browser.webViewRuntime.compositorRuntime.registerContainer(
            container,
            for: fixture.window.id,
            immediateVisualHandoffHandler: {
                handoffCount += 1
                return true
            }
        )

        XCTAssertTrue(
            fixture.visuals.performImmediateVisualHandoffIfPossible(
                in: fixture.window
            )
        )
        XCTAssertEqual(handoffCount, 1)
        withExtendedLifetime(container) {}
    }

    func testCancelDropsDeferredWindowMutation() async {
        let fixture = VisualFixture()
        fixture.tab.navigationRuntime.navigationTransactionOwner
            .pendingMainFrameNavigationKind = .backForward

        fixture.visuals.refreshCompositor(for: fixture.window)
        fixture.visuals.cancelWindowMutationsAfterHistorySwipe(in: fixture.window.id)
        fixture.tab.navigationRuntime.navigationTransactionOwner
            .pendingMainFrameNavigationKind = nil
        fixture.visuals.flushWindowMutationsAfterHistorySwipe(in: fixture.window.id)
        await drainMainQueue()

        XCTAssertEqual(fixture.window.compositorInvalidation.compositorVersion, 0)
    }
}

@MainActor
private final class VisualFixture {
    let browser = BrowserManager()
    let window = BrowserWindowState()
    let tab: Tab

    var visuals: BrowserWindowVisualCoordinator {
        browser.shellRuntime.windowVisuals
    }

    init() {
        let space = browser.spaceStateOwner.currentSpace
            ?? installTestSpace(
                in: browser.spaceStateOwner,
                name: "Visual fixture"
            )
        tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://visual-fixture.example",
            in: space,
            activate: true
        )
        browser.tabResidenceAuthority.establishResidenceSession(on: window)
        window.currentSpaceId = space.id
        window.currentTabId = tab.id
        browser.windowRegistry.register(window)
    }

    func beginHistorySwipe() -> WKWebView {
        let webView: WKWebView
        if let tracked = browser.webViewSessions.webView(
            for: tab.id,
            in: window.id
        ) {
            webView = tracked
        } else {
            let candidate = FocusableWKWebView()
            candidate.owningTab = tab
            let outcome = browser.webViewRuntime.trackedWebViewAdmission
                .registerAuxiliaryTrackedWebView(
                    candidate,
                    for: tab,
                    in: window.id
                )
            XCTAssertTrue(outcome.isAccepted)
            webView = candidate
        }
        browser.webViewRuntime.protectionRuntime.beginHistorySwipe(
            tabID: tab.id,
            webView: webView,
            originURL: nil,
            originHistoryItem: nil
        )
        return webView
    }
}

private func drainMainQueue() async {
    await Task.yield()
    await Task.yield()
}
