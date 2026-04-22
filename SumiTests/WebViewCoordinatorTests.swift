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
            in: windowId
        )

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

    func testSetWebViewReplacesReverseIndexForOverwrittenSlot() {
        let coordinator = WebViewCoordinator()
        let tabId = UUID()
        let windowId = UUID()
        let firstWebView = WKWebView(frame: .zero)
        let replacementWebView = WKWebView(frame: .zero)

        coordinator.setWebView(firstWebView, for: tabId, in: windowId)
        coordinator.setWebView(replacementWebView, for: tabId, in: windowId)

        XCTAssertNil(coordinator.windowID(containing: firstWebView))
        XCTAssertEqual(coordinator.windowID(containing: replacementWebView), windowId)
        XCTAssertTrue(coordinator.getWebView(for: tabId, in: windowId) === replacementWebView)
        XCTAssertTrue(coordinator.getWebViewHost(for: tabId, in: windowId)?.webView === replacementWebView)
    }

    func testWindowIDContainingWebViewUsesReverseIndexAcrossWindows() {
        let coordinator = WebViewCoordinator()
        let tabId = UUID()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let firstWebView = WKWebView(frame: .zero)
        let secondWebView = WKWebView(frame: .zero)

        coordinator.setWebView(firstWebView, for: tabId, in: firstWindowId)
        coordinator.setWebView(secondWebView, for: tabId, in: secondWindowId)

        XCTAssertEqual(coordinator.windowID(containing: firstWebView), firstWindowId)
        XCTAssertEqual(coordinator.windowID(containing: secondWebView), secondWindowId)
        XCTAssertTrue(coordinator.getWebViewHost(for: tabId, in: firstWindowId)?.webView === firstWebView)
        XCTAssertTrue(coordinator.getWebViewHost(for: tabId, in: secondWindowId)?.webView === secondWebView)
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

        let webView = coordinator.getOrCreateWebView(
            for: tab,
            in: windowId
        )
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

    func testDeferredAttachHostCommandsCollapseToLatestPane() async {
        let coordinator = WebViewCoordinator()
        let tabId = UUID()
        let windowId = UUID()
        let (root, singlePane, leftPane, _) = makeCompositorPaneRoot()
        let webView = WKWebView(frame: .zero)

        coordinator.setCompositorContainerView(root, for: windowId)
        coordinator.setWebView(webView, for: tabId, in: windowId)
        let host = try! XCTUnwrap(coordinator.getWebViewHost(for: tabId, in: windowId))

        coordinator.beginHistorySwipeProtection(
            tabId: tabId,
            webView: webView,
            originURL: URL(string: "https://example.com/collapse"),
            originHistoryItem: nil
        )

        XCTAssertFalse(coordinator.attachHost(host, to: singlePane))

        XCTAssertFalse(coordinator.attachHost(host, to: leftPane))

        coordinator.finishHistorySwipeProtection(
            tabId: tabId,
            webView: webView,
            currentURL: URL(string: "https://example.com/collapse-finished"),
            currentHistoryItem: nil
        )
        await Task.yield()

        XCTAssertTrue(host.superview === leftPane)
    }

    func testDeferredCommandsDropWhenWindowContainerIsDestroyed() {
        let coordinator = WebViewCoordinator()
        let tabId = UUID()
        let windowId = UUID()
        let (root, _, leftPane, _) = makeCompositorPaneRoot()
        let webView = WKWebView(frame: .zero)

        coordinator.setCompositorContainerView(root, for: windowId)
        coordinator.setWebView(webView, for: tabId, in: windowId)
        let host = try! XCTUnwrap(coordinator.getWebViewHost(for: tabId, in: windowId))

        coordinator.beginHistorySwipeProtection(
            tabId: tabId,
            webView: webView,
            originURL: URL(string: "https://example.com/drop-window"),
            originHistoryItem: nil
        )

        XCTAssertFalse(coordinator.attachHost(host, to: leftPane))

        coordinator.removeCompositorContainerView(for: windowId)

        XCTAssertNil(host.superview)
    }

    func testCleanupWindowDeferredCommandsAreRemovedAfterProtectedFlush() async {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/cleanup-protected-window",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let windowId = UUID()
        let webView = WKWebView(frame: .zero)

        coordinator.setWebView(webView, for: tab.id, in: windowId)
        tab.assignWebViewToWindow(webView, windowId: windowId)

        coordinator.beginHistorySwipeProtection(
            tabId: tab.id,
            webView: webView,
            originURL: tab.url,
            originHistoryItem: nil
        )
        coordinator.cleanupWindow(windowId, tabManager: browserManager.tabManager)

        XCTAssertNotNil(coordinator.getWebView(for: tab.id, in: windowId))

        coordinator.finishHistorySwipeProtection(
            tabId: tab.id,
            webView: webView,
            currentURL: URL(string: "https://example.com/cleanup-protected-window-finished"),
            currentHistoryItem: nil
        )
        await Task.yield()

        XCTAssertNil(coordinator.getWebView(for: tab.id, in: windowId))
    }

    func testProtectedHiddenWebViewDeferredEvictionFlushesAfterSwipeFinishes() async {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (registry, windowState) = makeWindowContext(browserManager: browserManager)

        let firstTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/protected-hidden-first",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let secondTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/protected-hidden-second",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let thirdTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/protected-hidden-third",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        setCurrentTab(firstTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)

        setCurrentTab(secondTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        let secondWebView = try! XCTUnwrap(coordinator.getWebView(for: secondTab.id, in: windowState.id))

        setCurrentTab(thirdTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        XCTAssertNil(coordinator.getWebView(for: firstTab.id, in: windowState.id))

        coordinator.beginHistorySwipeProtection(
            tabId: secondTab.id,
            webView: secondWebView,
            originURL: secondTab.url,
            originHistoryItem: nil
        )

        setCurrentTab(firstTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)

        XCTAssertNotNil(coordinator.getWebView(for: firstTab.id, in: windowState.id))
        XCTAssertNotNil(coordinator.getWebView(for: thirdTab.id, in: windowState.id))
        XCTAssertNotNil(coordinator.getWebView(for: secondTab.id, in: windowState.id))

        coordinator.finishHistorySwipeProtection(
            tabId: secondTab.id,
            webView: secondWebView,
            currentURL: URL(string: "https://example.com/protected-hidden-second-finished"),
            currentHistoryItem: nil
        )
        let evictionExpectation = expectation(
            description: "Protected hidden eviction settles after deferred flush"
        )
        Task { @MainActor in
            for _ in 0..<32 {
                let trackedWebViewCount = [
                    firstTab.id,
                    secondTab.id,
                    thirdTab.id,
                ].compactMap { coordinator.getWebView(for: $0, in: windowState.id) }.count
                if trackedWebViewCount == 2 {
                    evictionExpectation.fulfill()
                    return
                }
                await Task.yield()
            }
        }
        await fulfillment(of: [evictionExpectation], timeout: 1.0)

        XCTAssertNotNil(coordinator.getWebView(for: firstTab.id, in: windowState.id))
        XCTAssertEqual(
            [
                coordinator.getWebView(for: secondTab.id, in: windowState.id),
                coordinator.getWebView(for: thirdTab.id, in: windowState.id),
            ].compactMap { $0 }.count,
            1
        )
        _ = registry
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
            in: windowState.id
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
            in: windowState.id
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
            in: windowState.id
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

    func testRemoveAllWebViewsClearsReverseIndexEntries() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/remove-all",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let firstWebView = WKWebView(frame: .zero)
        let secondWebView = WKWebView(frame: .zero)

        coordinator.setWebView(firstWebView, for: tab.id, in: firstWindowId)
        coordinator.setWebView(secondWebView, for: tab.id, in: secondWindowId)
        tab.assignWebViewToWindow(firstWebView, windowId: firstWindowId)

        XCTAssertTrue(coordinator.removeAllWebViews(for: tab))

        XCTAssertNil(coordinator.getWebView(for: tab.id, in: firstWindowId))
        XCTAssertNil(coordinator.getWebView(for: tab.id, in: secondWindowId))
        XCTAssertNil(coordinator.getWebViewHost(for: tab.id, in: firstWindowId))
        XCTAssertNil(coordinator.getWebViewHost(for: tab.id, in: secondWindowId))
        XCTAssertNil(coordinator.windowID(containing: firstWebView))
        XCTAssertNil(coordinator.windowID(containing: secondWebView))
        XCTAssertNil(tab.primaryWindowId)
        XCTAssertNil(tab.assignedWebView)
    }

    func testCleanupWindowPromotesRemainingTrackedWebViewAndClearsClosedWindowIndex() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/cleanup-window",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let firstWebView = WKWebView(frame: .zero)
        let secondWebView = WKWebView(frame: .zero)

        coordinator.setWebView(firstWebView, for: tab.id, in: firstWindowId)
        coordinator.setWebView(secondWebView, for: tab.id, in: secondWindowId)
        tab.assignWebViewToWindow(firstWebView, windowId: firstWindowId)

        coordinator.cleanupWindow(firstWindowId, tabManager: browserManager.tabManager)

        XCTAssertNil(coordinator.getWebView(for: tab.id, in: firstWindowId))
        XCTAssertNil(coordinator.getWebViewHost(for: tab.id, in: firstWindowId))
        XCTAssertNil(coordinator.windowID(containing: firstWebView))
        XCTAssertEqual(coordinator.windowID(containing: secondWebView), secondWindowId)
        XCTAssertTrue(coordinator.getWebViewHost(for: tab.id, in: secondWindowId)?.webView === secondWebView)
        XCTAssertEqual(tab.primaryWindowId, secondWindowId)
        XCTAssertTrue(tab.assignedWebView === secondWebView)
    }

    func testCleanupAllWebViewsClearsReverseIndexEntries() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator

        let firstTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/full-cleanup-a",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let secondTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/full-cleanup-b",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let firstWebView = WKWebView(frame: .zero)
        let secondWebView = WKWebView(frame: .zero)

        coordinator.setWebView(firstWebView, for: firstTab.id, in: firstWindowId)
        coordinator.setWebView(secondWebView, for: secondTab.id, in: secondWindowId)
        firstTab.assignWebViewToWindow(firstWebView, windowId: firstWindowId)
        secondTab.assignWebViewToWindow(secondWebView, windowId: secondWindowId)

        coordinator.cleanupAllWebViews(tabManager: browserManager.tabManager)

        XCTAssertNil(coordinator.windowID(containing: firstWebView))
        XCTAssertNil(coordinator.windowID(containing: secondWebView))
        XCTAssertNil(coordinator.getWebView(for: firstTab.id, in: firstWindowId))
        XCTAssertNil(coordinator.getWebView(for: secondTab.id, in: secondWindowId))
        XCTAssertNil(coordinator.getWebViewHost(for: firstTab.id, in: firstWindowId))
        XCTAssertNil(coordinator.getWebViewHost(for: secondTab.id, in: secondWindowId))
        XCTAssertNil(firstTab.primaryWindowId)
        XCTAssertNil(secondTab.primaryWindowId)
    }

    func testPrepareVisibleWebViewsRetainsOnlyOneWarmHiddenWebViewPerWindow() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let firstTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/retention-first",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let secondTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/retention-second",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let thirdTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/retention-third",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        setCurrentTab(firstTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        let firstWebView = try! XCTUnwrap(coordinator.getWebView(for: firstTab.id, in: windowState.id))

        setCurrentTab(secondTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        let secondWebView = try! XCTUnwrap(coordinator.getWebView(for: secondTab.id, in: windowState.id))
        XCTAssertNotNil(coordinator.getWebView(for: firstTab.id, in: windowState.id))

        setCurrentTab(thirdTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        let thirdWebView = try! XCTUnwrap(coordinator.getWebView(for: thirdTab.id, in: windowState.id))

        XCTAssertNil(coordinator.getWebView(for: firstTab.id, in: windowState.id))
        XCTAssertNil(coordinator.windowID(containing: firstWebView))
        XCTAssertEqual(coordinator.windowID(containing: secondWebView), windowState.id)
        XCTAssertEqual(coordinator.windowID(containing: thirdWebView), windowState.id)
        XCTAssertNotNil(coordinator.getWebView(for: secondTab.id, in: windowState.id))
        XCTAssertNotNil(coordinator.getWebView(for: thirdTab.id, in: windowState.id))
    }

    func testPrepareVisibleWebViewsDoesNotEvictSplitVisibleWebViews() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let leftTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/split-left-visible",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let rightTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/split-right-visible",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let hiddenTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/split-hidden-evict",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let secondHiddenTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/split-hidden-evict-second",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        setCurrentTab(leftTab, in: windowState)
        browserManager.splitManager.enterSplit(
            with: rightTab,
            placeOn: .right,
            in: windowState,
            animate: false
        )

        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        let leftWebView = try! XCTUnwrap(coordinator.getWebView(for: leftTab.id, in: windowState.id))
        let rightWebView = try! XCTUnwrap(coordinator.getWebView(for: rightTab.id, in: windowState.id))
        let hiddenWebView = coordinator.getOrCreateWebView(
            for: hiddenTab,
            in: windowState.id
        )
        let secondHiddenWebView = coordinator.getOrCreateWebView(
            for: secondHiddenTab,
            in: windowState.id
        )

        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)

        XCTAssertTrue(coordinator.getWebView(for: leftTab.id, in: windowState.id) === leftWebView)
        XCTAssertTrue(coordinator.getWebView(for: rightTab.id, in: windowState.id) === rightWebView)
        XCTAssertNil(coordinator.getWebView(for: hiddenTab.id, in: windowState.id))
        XCTAssertNil(coordinator.getWebView(for: secondHiddenTab.id, in: windowState.id))
        XCTAssertNil(coordinator.windowID(containing: hiddenWebView))
        XCTAssertNil(coordinator.windowID(containing: secondHiddenWebView))
    }

    private func setCurrentTab(_ tab: Tab, in windowState: BrowserWindowState) {
        windowState.currentTabId = tab.id
        windowState.currentSpaceId = tab.spaceId
        windowState.isShowingEmptyState = false
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

    private func makeCompositorPaneRoot() -> (NSView, NSView, NSView, NSView) {
        let root = NSView()
        let singlePane = NSView()
        let leftPane = NSView()
        let rightPane = NSView()

        singlePane.identifier = CompositorPaneDestination.single.viewIdentifier
        leftPane.identifier = CompositorPaneDestination.left.viewIdentifier
        rightPane.identifier = CompositorPaneDestination.right.viewIdentifier

        root.addSubview(singlePane)
        root.addSubview(leftPane)
        root.addSubview(rightPane)

        return (root, singlePane, leftPane, rightPane)
    }
}
