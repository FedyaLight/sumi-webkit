import XCTest
import WebKit

@testable import Sumi

@MainActor
final class GlanceManagerTests: XCTestCase {
    func testSameURLPresentationIsNoOp() throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)

        XCTAssertTrue(browserManager.glanceManager.currentSession === session)
        XCTAssertEqual(browserManager.glanceManager.phase, .opening)
    }

    func testDifferentURLPresentationReplacesAndCleansOldPreview() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let firstURL = URL(string: "https://first.example/page")!
        let secondURL = URL(string: "https://second.example/page")!

        browserManager.glanceManager.presentExternalURL(firstURL, from: sourceTab)
        let firstSession = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let firstPreviewTab = firstSession.previewTab
        _ = try await waitForPreviewWebView(in: firstSession)
        XCTAssertNotNil(firstPreviewTab.existingWebView)

        browserManager.glanceManager.presentExternalURL(secondURL, from: sourceTab)

        let secondSession = try XCTUnwrap(browserManager.glanceManager.currentSession)
        XCTAssertNotEqual(secondSession.id, firstSession.id)
        XCTAssertEqual(secondSession.currentURL, secondURL)
        XCTAssertNil(firstPreviewTab.existingWebView)
    }

    func testDismissCleansPreviewAndReturnsIdle() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        _ = try await waitForPreviewWebView(in: session)
        XCTAssertNotNil(previewTab.existingWebView)

        browserManager.glanceManager.finishAnimatedDismissal(sessionID: session.id)

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertFalse(browserManager.glanceManager.isActive)
        XCTAssertNil(previewTab.existingWebView)
    }

    func testDismissGlanceImmediatelyClearsPreviewInstance() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        _ = try await waitForPreviewWebView(in: session)

        browserManager.glanceManager.dismissGlance()

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertFalse(browserManager.glanceManager.isActive)
        XCTAssertNil(previewTab.existingWebView)
        XCTAssertNil(previewTab.primaryWindowId)
    }

    func testWebKitCloseDismissesAndCleansPreviewInstance() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        let webView = try await waitForPreviewWebView(in: session)

        XCTAssertTrue(browserManager.handleWebViewDidClose(webView))

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertNil(previewTab.existingWebView)
        XCTAssertNil(previewTab.primaryWindowId)
    }

    func testWebKitCloseForTrackedRegularWebViewClosesOwningTab() throws {
        let browserManager = BrowserManager()
        browserManager.webViewCoordinator = WebViewCoordinator()
        let sourceTab = makeSourceTab(in: browserManager)
        let (_, sourceWindow) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let webView = WKWebView()

        browserManager.webViewCoordinator?.setWebView(
            webView,
            for: sourceTab.id,
            in: sourceWindow.id
        )

        XCTAssertTrue(browserManager.handleWebViewDidClose(webView))

        XCTAssertNil(browserManager.tabManager.tab(for: sourceTab.id))
        XCTAssertNil(browserManager.webViewCoordinator?.getWebView(
            for: sourceTab.id,
            in: sourceWindow.id
        ))
    }

    func testMoveToNewTabAdoptsSamePreviewTabAndWebView() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        let webView = try await waitForPreviewWebView(in: session)

        browserManager.glanceManager.moveToNewTab()

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertTrue(browserManager.tabManager.tab(for: previewTab.id) === previewTab)
        XCTAssertTrue(previewTab.existingWebView === webView)
    }

    func testMoveToNewTabPromotesPreviewInSourceWindow() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, sourceWindow) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let otherWindow = BrowserWindowState()
        otherWindow.tabManager = browserManager.tabManager
        windowRegistry.register(otherWindow)
        windowRegistry.setActive(otherWindow)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        let webView = try await waitForPreviewWebView(in: session)

        browserManager.glanceManager.moveToNewTab()

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertTrue(browserManager.tabManager.tab(for: previewTab.id) === previewTab)
        XCTAssertTrue(previewTab.existingWebView === webView)
        XCTAssertEqual(sourceWindow.currentTabId, previewTab.id)
        XCTAssertNotEqual(otherWindow.currentTabId, previewTab.id)
    }

    func testMoveToNewTabCanWaitForDisplayAttachmentBeforeFinishingPromotion() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, sourceWindow) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        _ = try await waitForPreviewWebView(in: session)

        browserManager.glanceManager.moveToNewTab(finishesAfterDisplayUpdate: true)

        XCTAssertTrue(browserManager.glanceManager.currentSession === session)
        XCTAssertEqual(browserManager.glanceManager.phase, .promoting)
        XCTAssertTrue(browserManager.tabManager.tab(for: previewTab.id) === previewTab)
        XCTAssertNotNil(previewTab.existingWebView)
        XCTAssertEqual(sourceWindow.currentTabId, previewTab.id)

        browserManager.glanceManager.finishPromotedSession(sessionID: session.id)

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        withExtendedLifetime(windowRegistry) {}
    }

    func testPromotionTargetLayoutKeepsTopAndBottomChromeGutters() {
        let frame = GlancePromotionTargetLayout.contentFrame(
            in: CGRect(x: 0, y: 0, width: 1000, height: 700),
            isSidebarVisible: false,
            sidebarWidth: 0,
            sidebarPosition: .left,
            elementSeparation: 8
        )

        XCTAssertEqual(frame, CGRect(x: 8, y: 8, width: 984, height: 684))
    }

    func testPromotionTargetLayoutDoesNotAddExtraGutterBesideDockedSidebar() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)

        let leftSidebarFrame = GlancePromotionTargetLayout.contentFrame(
            in: bounds,
            isSidebarVisible: true,
            sidebarWidth: 220,
            sidebarPosition: .left,
            elementSeparation: 8
        )
        let rightSidebarFrame = GlancePromotionTargetLayout.contentFrame(
            in: bounds,
            isSidebarVisible: true,
            sidebarWidth: 220,
            sidebarPosition: .right,
            elementSeparation: 8
        )

        XCTAssertEqual(leftSidebarFrame, CGRect(x: 220, y: 8, width: 772, height: 684))
        XCTAssertEqual(rightSidebarFrame, CGRect(x: 8, y: 8, width: 772, height: 684))
    }

    func testMoveToSplitViewPromotesPreviewIntoSourceWindowSplit() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, sourceWindow) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        let webView = try await waitForPreviewWebView(in: session)

        browserManager.glanceManager.moveToSplitView()

        let splitGroup = try XCTUnwrap(browserManager.tabManager.splitGroup(containing: previewTab.id))
        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertEqual(splitGroup.tabIds, [sourceTab.id, previewTab.id])
        XCTAssertEqual(splitGroup.activeTabId, previewTab.id)
        XCTAssertEqual(windowRegistry.activeWindow?.id, sourceWindow.id)
        XCTAssertEqual(sourceWindow.currentTabId, previewTab.id)
        XCTAssertTrue(previewTab.existingWebView === webView)
    }

    func testGlancePresentationStaysPinnedToSourceTabSelection() throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let otherTab = browserManager.tabManager.createNewTab(
            url: "https://other.example/page",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = sourceTab.spaceId
        windowState.currentTabId = sourceTab.id

        let previewTab = Tab(
            url: URL(string: "https://destination.example/page")!,
            name: "Destination",
            browserManager: browserManager
        )
        let session = GlanceSession(
            targetURL: previewTab.url,
            windowId: windowState.id,
            sourceTab: sourceTab,
            previewTab: previewTab,
            originRectInWindow: CGRect(x: 10, y: 10, width: 44, height: 44)
        )
        browserManager.glanceManager.currentSession = session
        browserManager.glanceManager.transition(to: .open)

        XCTAssertTrue(browserManager.glanceManager.presentedSession(for: windowState) === session)
        XCTAssertTrue(browserManager.glanceManager.activePreviewTab(for: windowState) === previewTab)

        windowState.currentTabId = otherTab.id

        XCTAssertNil(browserManager.glanceManager.presentedSession(for: windowState))
        XCTAssertNil(browserManager.glanceManager.activePreviewTab(for: windowState))
        XCTAssertTrue(browserManager.glanceManager.currentSession === session)
        XCTAssertTrue(browserManager.glanceManager.sidebarSession(for: windowState) === session)

        windowState.currentTabId = sourceTab.id

        XCTAssertTrue(browserManager.glanceManager.presentedSession(for: windowState) === session)
    }

    func testGlancePreviewPermissionSurfaceCountsAsActiveAndVisible() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, _) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        let webView = try await waitForPreviewWebView(in: session)

        XCTAssertFalse(previewTab.isCurrentTab)
        XCTAssertNil(previewTab.primaryWindowId)
        XCTAssertTrue(previewTab.permissionRequestIsActiveSurface(for: webView))
        XCTAssertTrue(previewTab.permissionRequestIsVisibleSurface(for: webView))
        XCTAssertFalse(previewTab.permissionRequestIsActiveSurface(for: WKWebView()))
        XCTAssertFalse(previewTab.permissionRequestIsVisibleSurface(for: WKWebView()))
        withExtendedLifetime(windowRegistry) {}
    }

    @discardableResult
    private func makeRegisteredWindow(
        in browserManager: BrowserManager,
        selecting tab: Tab
    ) -> (WindowRegistry, BrowserWindowState) {
        let windowRegistry = browserManager.windowRegistry ?? WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = tab.spaceId
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (windowRegistry, windowState)
    }

    private func makeSourceTab(in browserManager: BrowserManager) -> Tab {
        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Glance Tests")
        return browserManager.tabManager.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: true
        )
    }

    private func waitForPreviewWebView(
        in session: GlanceSession,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> WKWebView {
        for _ in 0..<20 {
            if let webView = session.previewTab.existingWebView {
                return webView
            }
            await Task.yield()
        }
        return try XCTUnwrap(session.previewTab.existingWebView, file: file, line: line)
    }
}
