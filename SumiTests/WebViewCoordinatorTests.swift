import Combine
import WebKit
import XCTest
@testable import Sumi

@MainActor
final class WebViewCoordinatorTests: XCTestCase {
    func testVisibleTabPreparationPlanReturnsCurrentTabForSinglePane() {
        let currentTabId = UUID()

        XCTAssertEqual(
            VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: currentTabId,
                isSplit: false,
                leftTabId: nil,
                rightTabId: nil,
                isPreviewActive: false
            ),
            [currentTabId]
        )
    }

    func testVisibleTabPreparationPlanReturnsBothSplitTabsForActiveSplitPane() {
        let leftTabId = UUID()
        let rightTabId = UUID()

        XCTAssertEqual(
            VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: leftTabId,
                isSplit: true,
                leftTabId: leftTabId,
                rightTabId: rightTabId,
                isPreviewActive: false
            ),
            [leftTabId, rightTabId]
        )
    }

    func testVisibleTabPreparationPlanKeepsCurrentTabDuringPreview() {
        let currentTabId = UUID()
        let leftTabId = UUID()
        let rightTabId = UUID()

        XCTAssertEqual(
            VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: currentTabId,
                isSplit: true,
                leftTabId: leftTabId,
                rightTabId: rightTabId,
                isPreviewActive: true
            ),
            [currentTabId]
        )
    }

    func testWebViewSyncLoadPolicySkipsOriginatingWebView() {
        let desiredURL = URL(string: "https://example.com/current")!

        XCTAssertFalse(
            WebViewSyncLoadPolicy.shouldLoadTarget(
                desiredURL: desiredURL,
                targetURL: nil,
                targetHistoryURL: nil,
                isOriginatingWebView: true
            )
        )
    }

    func testWebViewSyncLoadPolicySkipsMatchingCurrentURL() {
        let desiredURL = URL(string: "https://example.com/current")!

        XCTAssertFalse(
            WebViewSyncLoadPolicy.shouldLoadTarget(
                desiredURL: desiredURL,
                targetURL: desiredURL,
                targetHistoryURL: nil,
                isOriginatingWebView: false
            )
        )
    }

    func testWebViewSyncLoadPolicySkipsMatchingHistoryURL() {
        let desiredURL = URL(string: "https://example.com/current")!

        XCTAssertFalse(
            WebViewSyncLoadPolicy.shouldLoadTarget(
                desiredURL: desiredURL,
                targetURL: URL(string: "https://example.com/old"),
                targetHistoryURL: desiredURL,
                isOriginatingWebView: false
            )
        )
    }

    func testWebViewSyncLoadPolicyLoadsLaggingClone() {
        let desiredURL = URL(string: "https://example.com/current")!

        XCTAssertTrue(
            WebViewSyncLoadPolicy.shouldLoadTarget(
                desiredURL: desiredURL,
                targetURL: URL(string: "https://example.com/old"),
                targetHistoryURL: URL(string: "https://example.com/older"),
                isOriginatingWebView: false
            )
        )
    }

    func testGetOrCreateWebViewAdoptsPreCreatedTabWebViewAsPrimary() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/adopt",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.setupWebView()

        let preCreatedWebView = try! XCTUnwrap(tab.existingWebView)
        let windowId = UUID()

        let resolvedWebView = coordinator.getOrCreateWebView(
            for: tab,
            in: windowId,
            tabManager: browserManager.tabManager
        )

        XCTAssertTrue(resolvedWebView === preCreatedWebView)
        XCTAssertTrue(coordinator.getWebView(for: tab.id, in: windowId) === preCreatedWebView)
        XCTAssertEqual(tab.primaryWindowId, windowId)
    }

    func testCreateWebViewAdoptsPreCreatedTabWebViewAsPrimary() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/adopt-direct",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.setupWebView()

        let preCreatedWebView = try! XCTUnwrap(tab.existingWebView)
        let windowId = UUID()

        let resolvedWebView = coordinator.createWebView(for: tab, in: windowId)

        XCTAssertTrue(resolvedWebView === preCreatedWebView)
        XCTAssertTrue(coordinator.getWebView(for: tab.id, in: windowId) === preCreatedWebView)
        XCTAssertEqual(tab.primaryWindowId, windowId)
    }

    func testRemoveWebViewFromContainersDescendsIntoPaneHierarchy() {
        let coordinator = WebViewCoordinator()
        let windowId = UUID()
        let container = NSView()
        let pane = NSView()
        let webView = WKWebView(frame: .zero)
        container.addSubview(pane)
        pane.addSubview(webView)

        coordinator.setCompositorContainerView(container, for: windowId)
        coordinator.removeWebViewFromContainers(webView)

        XCTAssertNil(webView.superview)
        XCTAssertEqual(pane.subviews.count, 0)
    }

    func testSetWebViewCreatesStableHostContainer() {
        let coordinator = WebViewCoordinator()
        let tabId = UUID()
        let windowId = UUID()
        let webView = WKWebView(frame: .zero)

        coordinator.setWebView(webView, for: tabId, in: windowId)

        let host = coordinator.getWebViewHost(for: tabId, in: windowId)
        XCTAssertNotNil(host)
        XCTAssertTrue(host?.webView === webView)
        XCTAssertTrue(webView.superview === host)

        host?.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        host?.layoutSubtreeIfNeeded()
        XCTAssertEqual(webView.frame, host?.bounds)
    }

    func testCoordinatorCreatedWebViewUpdatesTabTitleFromKVO() async {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/title-observer",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let windowId = UUID()
        let expectation = expectation(description: "Tab title updates from WKWebView.title KVO")
        var cancellables: Set<AnyCancellable> = []

        tab.$name
            .dropFirst()
            .sink { title in
                if title == "Coordinator KVO Title" {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let webView = coordinator.createWebView(for: tab, in: windowId)
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head><title>Coordinator KVO Title</title></head>
              <body>Title observer regression</body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/title-observer")
        )

        await fulfillment(of: [expectation], timeout: 3.0)
        XCTAssertEqual(tab.name, "Coordinator KVO Title")
        _ = cancellables
    }

    func testProtectedWebViewContainerRemovalIsDeferredUntilSwipeFinishes() async {
        let coordinator = WebViewCoordinator()
        let tabId = UUID()
        let windowId = UUID()
        let root = NSView()
        let pane = NSView()
        let webView = WKWebView(frame: .zero)

        root.addSubview(pane)
        coordinator.setCompositorContainerView(root, for: windowId)
        coordinator.setWebView(webView, for: tabId, in: windowId)
        let host = try! XCTUnwrap(coordinator.getWebViewHost(for: tabId, in: windowId))
        pane.addSubview(host)

        coordinator.beginHistorySwipeProtection(
            tabId: tabId,
            webView: webView,
            originURL: URL(string: "https://example.com/a"),
            originHistoryItem: nil
        )
        coordinator.removeWebViewFromContainers(webView)

        XCTAssertTrue(host.superview === pane)
        XCTAssertTrue(webView.superview === host)

        coordinator.finishHistorySwipeProtection(
            tabId: tabId,
            webView: webView,
            currentURL: URL(string: "https://example.com/b"),
            currentHistoryItem: nil
        )
        await Task.yield()

        XCTAssertNil(host.superview)
        XCTAssertNil(webView.superview)
    }

    func testHistorySwipeMutationBarrierFlushesQueuedCompositorRefreshAfterSettle() async {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/barrier-refresh",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        windowState.currentTabId = tab.id
        windowState.currentSpaceId = tab.spaceId

        let webView = coordinator.getOrCreateWebView(
            for: tab,
            in: windowState.id,
            tabManager: browserManager.tabManager
        )

        coordinator.beginHistorySwipeProtection(
            tabId: tab.id,
            webView: webView,
            originURL: tab.url,
            originHistoryItem: nil
        )

        let initialVersion = windowState.compositorVersion
        browserManager.refreshCompositor(for: windowState)

        XCTAssertEqual(windowState.compositorVersion, initialVersion)

        browserManager.flushWindowMutationsAfterHistorySwipe(in: windowState.id)
        await Task.yield()

        XCTAssertEqual(windowState.compositorVersion, initialVersion + 1)
    }

    func testHistorySwipeMutationBarrierCancelDropsQueuedCompositorRefresh() async {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/barrier-cancel",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        windowState.currentTabId = tab.id
        windowState.currentSpaceId = tab.spaceId

        let webView = coordinator.getOrCreateWebView(
            for: tab,
            in: windowState.id,
            tabManager: browserManager.tabManager
        )

        coordinator.beginHistorySwipeProtection(
            tabId: tab.id,
            webView: webView,
            originURL: tab.url,
            originHistoryItem: nil
        )

        let initialVersion = windowState.compositorVersion
        browserManager.refreshCompositor(for: windowState)
        browserManager.cancelWindowMutationsAfterHistorySwipe(in: windowState.id)
        await Task.yield()

        XCTAssertEqual(windowState.compositorVersion, initialVersion)
    }

    func testHistorySwipeMutationBarrierFlushesQueuedVisiblePreparationAfterSettle() async {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let leftTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/barrier-left",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let rightTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/barrier-right",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        browserManager.selectTab(leftTab, in: windowState)
        browserManager.splitManager.enterSplit(
            with: rightTab,
            placeOn: .right,
            in: windowState,
            animate: false
        )

        let leftWebView = coordinator.getOrCreateWebView(
            for: leftTab,
            in: windowState.id,
            tabManager: browserManager.tabManager
        )

        coordinator.beginHistorySwipeProtection(
            tabId: leftTab.id,
            webView: leftWebView,
            originURL: leftTab.url,
            originHistoryItem: nil
        )

        XCTAssertNil(coordinator.getWebView(for: rightTab.id, in: windowState.id))

        browserManager.schedulePrepareVisibleWebViews(for: windowState)
        XCTAssertNil(coordinator.getWebView(for: rightTab.id, in: windowState.id))

        browserManager.flushWindowMutationsAfterHistorySwipe(in: windowState.id)
        await Task.yield()

        XCTAssertNotNil(coordinator.getWebView(for: rightTab.id, in: windowState.id))
    }

    func testBackForwardSettleDecisionTreatsReturnedURLAsCancelled() {
        let url = URL(string: "https://example.com/a")!

        XCTAssertFalse(
            BackForwardNavigationSettleDecision.shouldApplyDeferredActions(
                originURL: url,
                originHistoryURL: nil,
                originHistoryItem: nil,
                currentURL: url,
                currentHistoryURL: nil,
                currentHistoryItem: nil
            )
        )
    }

    func testPrepareVisibleWebViewsCreatesCurrentWindowWebView() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/prepare",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        browserManager.selectTab(tab, in: windowState)

        XCTAssertTrue(
            coordinator.prepareVisibleWebViews(
                for: windowState,
                browserManager: browserManager
            )
        )
        XCTAssertNotNil(coordinator.getWebView(for: tab.id, in: windowState.id))
    }

    func testPrepareVisibleWebViewsCreatesBothSplitPaneWebViews() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let leftTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/left",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let rightTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/right",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        browserManager.selectTab(leftTab, in: windowState)
        browserManager.splitManager.enterSplit(
            with: rightTab,
            placeOn: .right,
            in: windowState,
            animate: false
        )

        XCTAssertTrue(
            coordinator.prepareVisibleWebViews(
                for: windowState,
                browserManager: browserManager
            )
        )
        XCTAssertNotNil(coordinator.getWebView(for: leftTab.id, in: windowState.id))
        XCTAssertNotNil(coordinator.getWebView(for: rightTab.id, in: windowState.id))
    }

    private func makeWindowContext(
        browserManager: BrowserManager
    ) -> (WindowRegistry, BrowserWindowState) {
        let registry = WindowRegistry()
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager

        browserManager.windowRegistry = registry
        registry.register(windowState)
        registry.setActive(windowState)

        return (registry, windowState)
    }
}
