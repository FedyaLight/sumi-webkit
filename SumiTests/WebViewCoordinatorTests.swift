import Combine
import BrowserServicesKit
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

    func testSplitDropCaptureHitPolicyOnlyCapturesActiveCardRegions() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let verticalCenter = bounds.midY

        XCTAssertEqual(
            SplitDropCaptureHitPolicy.side(
                at: CGPoint(
                    x: SplitDropCaptureHitPolicy.cardPadding + (SplitDropCaptureHitPolicy.cardWidth / 2),
                    y: verticalCenter
                ),
                in: bounds
            ),
            .left
        )
        XCTAssertEqual(
            SplitDropCaptureHitPolicy.side(
                at: CGPoint(
                    x: bounds.maxX - SplitDropCaptureHitPolicy.cardPadding - (SplitDropCaptureHitPolicy.cardWidth / 2),
                    y: verticalCenter
                ),
                in: bounds
            ),
            .right
        )
        XCTAssertNil(
            SplitDropCaptureHitPolicy.side(
                at: CGPoint(x: bounds.midX, y: verticalCenter),
                in: bounds
            )
        )
        XCTAssertFalse(
            SplitDropCaptureHitPolicy.shouldCaptureHit(
                at: CGPoint(
                    x: SplitDropCaptureHitPolicy.cardPadding + (SplitDropCaptureHitPolicy.cardWidth / 2),
                    y: verticalCenter
                ),
                in: bounds,
                isDragActive: false
            )
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

        let resolvedWebView = try! XCTUnwrap(coordinator.getOrCreateWebView(
            for: tab,
            in: windowId
        ))

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

        let host = try! XCTUnwrap(coordinator.getWebViewHost(for: tabId, in: windowId))
        XCTAssertTrue(host.webView === webView)
        XCTAssertTrue(webView.superview === host.webContentClipViewForTesting)

        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.webContentClipFrameForTesting, host.bounds)
        XCTAssertEqual(webView.frame, host.bounds)
    }

    func testWebViewHostInputExclusionRejectsHitTestingInsideRegionOnly() throws {
        let window = makeWindow()
        let webView = WKWebView(frame: .zero)
        let host = SumiWebViewContainerView(
            tabID: UUID(),
            windowID: UUID(),
            webView: webView
        )
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        window.contentView?.addSubview(host)
        host.layoutSubtreeIfNeeded()
        host.updateInputExclusionRegion(
            WebContentInputExclusionRegion(
                windowRects: [CGRect(x: 0, y: 0, width: 120, height: 240)]
            )
        )

        XCTAssertNil(host.hitTest(NSPoint(x: 40, y: 40)))
        XCTAssertNotNil(host.hitTest(NSPoint(x: 200, y: 40)))
    }

    func testWebViewHostInputExclusionClipsLeftEdgeWithoutMovingVisibleWebContent() {
        let window = makeWindow()
        let webView = WKWebView(frame: .zero)
        let host = SumiWebViewContainerView(
            tabID: UUID(),
            windowID: UUID(),
            webView: webView
        )
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        window.contentView?.addSubview(host)
        host.layoutSubtreeIfNeeded()

        host.updateInputExclusionRegion(
            WebContentInputExclusionRegion(
                windowRects: [CGRect(x: 0, y: 0, width: 120, height: 240)]
            )
        )

        XCTAssertEqual(
            host.webContentClipFrameForTesting,
            CGRect(x: 120, y: 0, width: 200, height: 240)
        )
        XCTAssertEqual(
            host.displayedWebContentFrameForTesting,
            CGRect(x: -120, y: 0, width: 320, height: 240)
        )
        XCTAssertNil(host.hitTest(NSPoint(x: 40, y: 40)))
        XCTAssertNotNil(host.hitTest(NSPoint(x: 200, y: 40)))

        host.updateInputExclusionRegion(.empty)

        XCTAssertEqual(host.webContentClipFrameForTesting, host.bounds)
        XCTAssertEqual(host.displayedWebContentFrameForTesting, host.bounds)
    }

    func testWebViewHostInputExclusionClipsRightEdgeWithoutMovingVisibleWebContent() {
        let window = makeWindow()
        let webView = WKWebView(frame: .zero)
        let host = SumiWebViewContainerView(
            tabID: UUID(),
            windowID: UUID(),
            webView: webView
        )
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        window.contentView?.addSubview(host)
        host.layoutSubtreeIfNeeded()

        host.updateInputExclusionRegion(
            WebContentInputExclusionRegion(
                windowRects: [CGRect(x: 200, y: 0, width: 120, height: 240)]
            )
        )

        XCTAssertEqual(
            host.webContentClipFrameForTesting,
            CGRect(x: 0, y: 0, width: 200, height: 240)
        )
        XCTAssertEqual(
            host.displayedWebContentFrameForTesting,
            CGRect(x: 0, y: 0, width: 320, height: 240)
        )
        XCTAssertNil(host.hitTest(NSPoint(x: 260, y: 40)))
        XCTAssertNotNil(host.hitTest(NSPoint(x: 40, y: 40)))
    }

    func testWebViewHostInputExclusionRejectsPointerEventsInsideRegion() {
        let window = makeWindow()
        let host = SumiWebViewContainerView(
            tabID: UUID(),
            windowID: UUID(),
            webView: WKWebView(frame: .zero)
        )
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        window.contentView?.addSubview(host)
        host.updateInputExclusionRegion(
            WebContentInputExclusionRegion(
                windowRects: [CGRect(x: 0, y: 0, width: 120, height: 240)]
            )
        )

        host.mouseMoved(with: makeMouseEvent(
            type: .mouseMoved,
            location: NSPoint(x: 40, y: 40),
            windowNumber: window.windowNumber
        ))
        host.cursorUpdate(with: makeMouseEvent(
            type: .cursorUpdate,
            location: NSPoint(x: 40, y: 40),
            windowNumber: window.windowNumber
        ))
        host.mouseEntered(with: makeMouseEvent(
            type: .mouseEntered,
            location: NSPoint(x: 40, y: 40),
            windowNumber: window.windowNumber
        ))
        host.mouseDown(with: makeMouseEvent(
            type: .leftMouseDown,
            location: NSPoint(x: 40, y: 40),
            windowNumber: window.windowNumber
        ))

        XCTAssertEqual(
            host.rejectedInputEventTypesForTesting,
            [.mouseMoved, .cursorUpdate, .mouseEntered, .leftMouseDown]
        )

        host.mouseMoved(with: makeMouseEvent(
            type: .mouseMoved,
            location: NSPoint(x: 200, y: 40),
            windowNumber: window.windowNumber
        ))
        XCTAssertEqual(host.rejectedInputEventTypesForTesting.count, 4)
    }

    func testWebContentInputExclusionEventGateSuppressesOnlyWebContentEvents() {
        XCTAssertTrue(WebContentInputExclusionEventGate.shouldSuppress(
            eventType: .cursorUpdate,
            isInExclusion: true,
            topHitIsWebContent: false,
            trackingAreaIsWebContent: true
        ))
        XCTAssertTrue(WebContentInputExclusionEventGate.shouldSuppress(
            eventType: .mouseMoved,
            isInExclusion: true,
            topHitIsWebContent: true,
            trackingAreaIsWebContent: false
        ))

        XCTAssertFalse(WebContentInputExclusionEventGate.shouldSuppress(
            eventType: .mouseMoved,
            isInExclusion: true,
            topHitIsWebContent: false,
            trackingAreaIsWebContent: true
        ))
        XCTAssertFalse(WebContentInputExclusionEventGate.shouldSuppress(
            eventType: .mouseMoved,
            isInExclusion: true,
            topHitIsWebContent: false,
            trackingAreaIsWebContent: false
        ))
        XCTAssertFalse(WebContentInputExclusionEventGate.shouldSuppress(
            eventType: .cursorUpdate,
            isInExclusion: true,
            topHitIsWebContent: false,
            trackingAreaIsWebContent: false
        ))
        XCTAssertFalse(WebContentInputExclusionEventGate.shouldSuppress(
            eventType: .cursorUpdate,
            isInExclusion: false,
            topHitIsWebContent: true,
            trackingAreaIsWebContent: true
        ))
    }

    func testCoordinatorInputExclusionEventGateUsesNarrowLocalMonitorLifecycle() {
        let windowId = UUID()
        var installedMasks: [NSEvent.EventTypeMask] = []
        var removedMonitorCount = 0
        let coordinator = WebViewCoordinator(
            inputExclusionEventMonitors: WebContentInputExclusionEventMonitorClient(
                addLocalMonitor: { mask, _ in
                    installedMasks.append(mask)
                    return NSObject()
                },
                removeMonitor: { _ in
                    removedMonitorCount += 1
                }
            )
        )

        coordinator.setInputExclusionRegion(
            WebContentInputExclusionRegion(
                windowRects: [CGRect(x: 0, y: 0, width: 120, height: 240)]
            ),
            for: windowId
        )
        coordinator.setInputExclusionRegion(
            WebContentInputExclusionRegion(
                windowRects: [CGRect(x: 0, y: 0, width: 100, height: 220)]
            ),
            for: windowId
        )

        XCTAssertEqual(installedMasks, [WebContentInputExclusionEventGate.monitoredEventTypes])
        XCTAssertEqual(WebContentInputExclusionEventGate.monitoredEventTypes, [.mouseMoved, .cursorUpdate])
        XCTAssertEqual(removedMonitorCount, 0)

        coordinator.setInputExclusionRegion(.empty, for: windowId)

        XCTAssertEqual(removedMonitorCount, 1)
    }

    func testCoordinatorInputExclusionClearsStaleWebHoverWithoutSuppressingSidebarMouseMove() throws {
        let coordinator = WebViewCoordinator()
        let window = makeWindow()
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 240))
        let tabId = UUID()
        let windowId = UUID()
        let webView = WKWebView(frame: .zero)

        window.contentView?.addSubview(root)
        coordinator.setCompositorContainerView(root, for: windowId)
        coordinator.setWebView(webView, for: tabId, in: windowId)
        let host = try XCTUnwrap(coordinator.getWebViewHost(for: tabId, in: windowId))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        root.addSubview(host)
        root.addSubview(sidebar)
        coordinator.setInputExclusionRegion(
            WebContentInputExclusionRegion(
                windowRects: [CGRect(x: 0, y: 0, width: 120, height: 240)]
            ),
            for: windowId
        )

        let insideSidebarEvent = makeMouseEvent(
            type: .mouseMoved,
            location: NSPoint(x: 40, y: 40),
            windowNumber: window.windowNumber
        )
        XCTAssertTrue(try XCTUnwrap(
            coordinator.handleInputExclusionEventForTesting(insideSidebarEvent)
        ) === insideSidebarEvent)
        XCTAssertEqual(host.inputExclusionPointerExitCountForTesting, 1)

        XCTAssertTrue(try XCTUnwrap(
            coordinator.handleInputExclusionEventForTesting(insideSidebarEvent)
        ) === insideSidebarEvent)
        XCTAssertEqual(host.inputExclusionPointerExitCountForTesting, 1)

        let outsideSidebarEvent = makeMouseEvent(
            type: .mouseMoved,
            location: NSPoint(x: 200, y: 40),
            windowNumber: window.windowNumber
        )
        XCTAssertTrue(try XCTUnwrap(
            coordinator.handleInputExclusionEventForTesting(outsideSidebarEvent)
        ) === outsideSidebarEvent)
        XCTAssertTrue(try XCTUnwrap(
            coordinator.handleInputExclusionEventForTesting(insideSidebarEvent)
        ) === insideSidebarEvent)
        XCTAssertEqual(host.inputExclusionPointerExitCountForTesting, 2)
    }

    func testWebViewHostInputExclusionInstallsLocalCursorBoundaryRects() {
        let window = makeWindow()
        let host = SumiWebViewContainerView(
            tabID: UUID(),
            windowID: UUID(),
            webView: WKWebView(frame: .zero)
        )
        host.frame = NSRect(x: 20, y: 10, width: 320, height: 240)
        window.contentView?.addSubview(host)

        host.updateInputExclusionRegion(
            WebContentInputExclusionRegion(
                windowRects: [CGRect(x: 0, y: 0, width: 120, height: 240)]
            )
        )

        XCTAssertEqual(host.inputExclusionLocalRectsForTesting, [
            CGRect(x: 0, y: 0, width: 100, height: 230),
        ])
        XCTAssertEqual(host.inputExclusionTrackingAreaRectsForTesting, [
            CGRect(x: 0, y: 0, width: 100, height: 230),
        ])

        host.updateInputExclusionRegion(.empty)

        XCTAssertTrue(host.inputExclusionLocalRectsForTesting.isEmpty)
        XCTAssertTrue(host.inputExclusionTrackingAreaRectsForTesting.isEmpty)
    }

    func testFocusableWebViewInputExclusionInstallsLocalCursorBoundaryRects() {
        let window = makeWindow()
        let webView = FocusableWKWebView(
            frame: NSRect(x: 30, y: 20, width: 320, height: 240),
            configuration: WKWebViewConfiguration()
        )
        window.contentView?.addSubview(webView)

        webView.updateInputExclusionRegion(
            WebContentInputExclusionRegion(
                windowRects: [CGRect(x: 0, y: 0, width: 150, height: 260)]
            )
        )

        XCTAssertEqual(webView.inputExclusionLocalRectsForTesting, [
            CGRect(x: 0, y: 0, width: 120, height: 240),
        ])
        XCTAssertEqual(webView.inputExclusionTrackingAreaRectsForTesting, [
            CGRect(x: 0, y: 0, width: 120, height: 240),
        ])

        webView.updateInputExclusionRegion(.empty)

        XCTAssertTrue(webView.inputExclusionLocalRectsForTesting.isEmpty)
        XCTAssertTrue(webView.inputExclusionTrackingAreaRectsForTesting.isEmpty)
    }

    func testCoordinatorAppliesInputExclusionToExistingAndFutureWebViewHosts() throws {
        let coordinator = WebViewCoordinator()
        let windowId = UUID()
        let firstTabId = UUID()
        let secondTabId = UUID()
        let region = WebContentInputExclusionRegion(
            windowRects: [CGRect(x: 0, y: 0, width: 120, height: 240)]
        )

        let firstWebView = WKWebView(frame: .zero)
        coordinator.setWebView(firstWebView, for: firstTabId, in: windowId)
        let firstHost = try XCTUnwrap(coordinator.getWebViewHost(for: firstTabId, in: windowId))
        firstHost.frame = NSRect(x: 0, y: 0, width: 320, height: 240)

        coordinator.setInputExclusionRegion(region, for: windowId)
        XCTAssertNil(firstHost.hitTest(NSPoint(x: 40, y: 40)))

        let secondWebView = WKWebView(frame: .zero)
        coordinator.setWebView(secondWebView, for: secondTabId, in: windowId)
        let secondHost = try XCTUnwrap(coordinator.getWebViewHost(for: secondTabId, in: windowId))
        secondHost.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        XCTAssertNil(secondHost.hitTest(NSPoint(x: 40, y: 40)))

        coordinator.setInputExclusionRegion(.empty, for: windowId)
        XCTAssertNotNil(firstHost.hitTest(NSPoint(x: 40, y: 40)))
        XCTAssertNotNil(secondHost.hitTest(NSPoint(x: 40, y: 40)))
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
            url: "about:blank",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let windowId = UUID()
        let expectation = expectation(description: "Tab title updates from WKWebView.title KVO")
        let expectedTitlePrefix = "Coordinator KVO Title"
        var cancellables: Set<AnyCancellable> = []

        tab.$name
            .dropFirst()
            .sink { title in
                if title.hasPrefix(expectedTitlePrefix) {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let webView = try! XCTUnwrap(coordinator.getOrCreateWebView(
            for: tab,
            in: windowId
        ))
        if let controller = webView.configuration.userContentController as? UserContentController {
            await controller.awaitContentBlockingAssetsInstalled()
        }
        await Task.yield()
        webView.stopLoading()
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head><title>Coordinator KVO Title 0</title></head>
              <body>Title observer regression</body>
              <script>
                let titleTick = 1;
                const titleTimer = setInterval(() => {
                  document.title = "Coordinator KVO Title " + titleTick;
                  titleTick += 1;
                  if (titleTick > 80) {
                    clearInterval(titleTimer);
                  }
                }, 50);
              </script>
            </html>
            """,
            baseURL: URL(string: "https://example.com/title-observer")
        )

        await fulfillment(of: [expectation], timeout: 10.0)
        XCTAssertTrue(tab.name.hasPrefix(expectedTitlePrefix))
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
        XCTAssertTrue(webView.superview === host.webContentClipViewForTesting)

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
        XCTAssertNotNil(coordinator.getWebView(for: firstTab.id, in: windowState.id))

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
                if trackedWebViewCount == 3 {
                    evictionExpectation.fulfill()
                    return
                }
                await Task.yield()
            }
        }
        await fulfillment(of: [evictionExpectation], timeout: 1.0)

        XCTAssertNotNil(coordinator.getWebView(for: firstTab.id, in: windowState.id))
        XCTAssertNotNil(coordinator.getWebView(for: secondTab.id, in: windowState.id))
        XCTAssertNotNil(coordinator.getWebView(for: thirdTab.id, in: windowState.id))
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

        let webView = try! XCTUnwrap(coordinator.getOrCreateWebView(
            for: tab,
            in: windowState.id
        ))

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

        let webView = try! XCTUnwrap(coordinator.getOrCreateWebView(
            for: tab,
            in: windowState.id
        ))

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

        let leftWebView = try! XCTUnwrap(coordinator.getOrCreateWebView(
            for: leftTab,
            in: windowState.id
        ))

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
        let webView = try! XCTUnwrap(coordinator.getWebView(for: tab.id, in: windowState.id))
        XCTAssertTrue(webView === tab.existingWebView)
        assertNormalTabWebView(webView, for: tab, browserManager: browserManager)
    }

    func testCloneWebViewUsesNormalTabRuntimePath() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (registry, firstWindow) = makeWindowContext(browserManager: browserManager)

        let secondWindow = BrowserWindowState()
        secondWindow.tabManager = browserManager.tabManager
        secondWindow.currentSpaceId = firstWindow.currentSpaceId
        registry.register(secondWindow)

        let sharedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/shared-normal-runtime",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        setCurrentTab(sharedTab, in: firstWindow)
        _ = coordinator.prepareVisibleWebViews(for: firstWindow, browserManager: browserManager)
        let primaryWebView = try! XCTUnwrap(coordinator.getWebView(for: sharedTab.id, in: firstWindow.id))

        setCurrentTab(sharedTab, in: secondWindow)
        _ = coordinator.prepareVisibleWebViews(for: secondWindow, browserManager: browserManager)
        let cloneWebView = try! XCTUnwrap(coordinator.getWebView(for: sharedTab.id, in: secondWindow.id))

        XCTAssertFalse(primaryWebView === cloneWebView)
        XCTAssertTrue(sharedTab.existingWebView === primaryWebView)
        XCTAssertEqual(coordinator.liveWebViews(for: sharedTab).count, 2)
        assertNormalTabWebView(primaryWebView, for: sharedTab, browserManager: browserManager)
        assertNormalTabWebView(cloneWebView, for: sharedTab, browserManager: browserManager)
    }

    func testDisabledModuleRegistryDoesNotChangeNormalWebViewCreation() {
        let defaults = TestDefaultsHarness()
        let moduleRegistry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults.defaults)
        )
        for moduleID in SumiModuleID.allCases {
            moduleRegistry.disable(moduleID)
        }

        let browserManager = BrowserManager(moduleRegistry: moduleRegistry)
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (_, windowState) = makeWindowContext(browserManager: browserManager)
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/modules-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        setCurrentTab(tab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        let webView = try! XCTUnwrap(coordinator.getWebView(for: tab.id, in: windowState.id))

        assertNormalTabWebView(webView, for: tab, browserManager: browserManager)
        for moduleID in SumiModuleID.allCases {
            XCTAssertFalse(moduleRegistry.isEnabled(moduleID))
        }
        defaults.reset()
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

    func testPrepareVisibleWebViewsDoesNotDeactivateSoleLiveHiddenTabInMaximumMode() throws {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let settings = installMemoryMode(.maximum, on: browserManager)
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let hiddenTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/maximum-hidden",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let selectedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/maximum-selected",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        setCurrentTab(hiddenTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        let hiddenWebView = try XCTUnwrap(coordinator.getWebView(for: hiddenTab.id, in: windowState.id))

        setCurrentTab(selectedTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)

        XCTAssertTrue(coordinator.getWebView(for: hiddenTab.id, in: windowState.id) === hiddenWebView)
        XCTAssertEqual(coordinator.windowID(containing: hiddenWebView), windowState.id)
        XCTAssertTrue(hiddenTab.existingWebView === hiddenWebView)
        XCTAssertEqual(hiddenTab.primaryWindowId, windowState.id)
        XCTAssertFalse(hiddenTab.isSuspended)
        XCTAssertTrue(browserManager.tabSuspensionService.proactiveTimerTabIDsForTesting.contains(hiddenTab.id))
        XCTAssertNotNil(coordinator.getWebView(for: selectedTab.id, in: windowState.id))
        _ = settings
    }

    func testSelectingSuspendedHiddenTabRestoresExactlyOneWebView() throws {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let settings = installMemoryMode(.maximum, on: browserManager)
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let suspendedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/restore-suspended",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let selectedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/restore-selected",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        setCurrentTab(suspendedTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        setCurrentTab(selectedTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        XCTAssertTrue(browserManager.tabSuspensionService.suspend(suspendedTab, reason: "test-restore"))

        XCTAssertTrue(suspendedTab.isSuspended)
        XCTAssertEqual(coordinator.liveWebViews(for: suspendedTab).count, 0)

        browserManager.selectTab(
            suspendedTab,
            in: windowState,
            loadPolicy: .immediate
        )
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        let restoredWebView = try XCTUnwrap(coordinator.getWebView(for: suspendedTab.id, in: windowState.id))

        XCTAssertFalse(suspendedTab.isSuspended)
        XCTAssertTrue(suspendedTab.existingWebView === restoredWebView)
        XCTAssertEqual(coordinator.liveWebViews(for: suspendedTab).count, 1)

        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        XCTAssertTrue(coordinator.getWebView(for: suspendedTab.id, in: windowState.id) === restoredWebView)
        XCTAssertEqual(coordinator.liveWebViews(for: suspendedTab).count, 1)
        _ = settings
    }

    func testURLSyncDoesNotResurrectSuspendedHiddenWebViews() throws {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let settings = installMemoryMode(.maximum, on: browserManager)
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let suspendedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/sync-hidden",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let selectedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/sync-selected",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        setCurrentTab(suspendedTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        setCurrentTab(selectedTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        XCTAssertTrue(browserManager.tabSuspensionService.suspend(suspendedTab, reason: "test-sync"))

        XCTAssertTrue(suspendedTab.isSuspended)
        suspendedTab.url = URL(string: "https://example.com/sync-updated")!
        browserManager.syncTabAcrossWindows(suspendedTab.id)

        XCTAssertNil(coordinator.getWebView(for: suspendedTab.id, in: windowState.id))
        XCTAssertNil(suspendedTab.existingWebView)
        XCTAssertEqual(coordinator.liveWebViews(for: suspendedTab).count, 0)
        _ = settings
    }

    func testRepeatedVisiblePreparationDoesNotRetryAlreadySuspendedTabs() throws {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let settings = installMemoryMode(.maximum, on: browserManager)
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let suspendedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/repeated-hidden",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let selectedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/repeated-selected",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        setCurrentTab(suspendedTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        let originalWebView = try XCTUnwrap(coordinator.getWebView(for: suspendedTab.id, in: windowState.id))

        setCurrentTab(selectedTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)
        XCTAssertTrue(browserManager.tabSuspensionService.suspend(suspendedTab, reason: "test-repeated"))
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)

        XCTAssertTrue(suspendedTab.isSuspended)
        XCTAssertNil(coordinator.windowID(containing: originalWebView))
        XCTAssertNil(coordinator.getWebView(for: suspendedTab.id, in: windowState.id))
        XCTAssertNil(suspendedTab.existingWebView)
        XCTAssertEqual(coordinator.liveWebViews(for: suspendedTab).count, 0)
        XCTAssertEqual(coordinator.liveWebViews(for: selectedTab).count, 1)
        _ = settings
    }

    func testHiddenCleanupDoesNotDeactivateSelectedVisibleOrEligibilityVetoedTabs() throws {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let settings = installMemoryMode(.maximum, on: browserManager)
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let selectedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/veto-selected",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let loadingTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/veto-loading",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let audioTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/veto-audio",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let pipTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/veto-pip",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let pdfTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/veto-pdf",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let pageVetoTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/veto-page",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let fileTab = browserManager.tabManager.createNewTab(
            url: "file:///tmp/sumi-hidden-veto.html",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let protectedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/veto-protected",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let eligibleTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/veto-eligible",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        let hiddenTabs = [
            loadingTab,
            audioTab,
            pipTab,
            pdfTab,
            pageVetoTab,
            fileTab,
            protectedTab,
            eligibleTab,
        ]
        var webViewsByTabID: [UUID: WKWebView] = [:]
        for tab in hiddenTabs {
            webViewsByTabID[tab.id] = try! XCTUnwrap(coordinator.getOrCreateWebView(
                for: tab,
                in: windowState.id
            ))
        }

        loadingTab.loadingState = .didCommit
        audioTab.applyAudioState(.unmuted(isPlayingAudio: true))
        pipTab.hasPictureInPictureVideo = true
        pdfTab.isDisplayingPDFDocument = true
        pageVetoTab.pageSuspensionVeto = .pageReportedUnableToSuspend
        coordinator.beginHistorySwipeProtection(
            tabId: protectedTab.id,
            webView: try XCTUnwrap(webViewsByTabID[protectedTab.id]),
            originURL: protectedTab.url,
            originHistoryItem: nil
        )

        setCurrentTab(selectedTab, in: windowState)
        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)

        XCTAssertNotNil(coordinator.getWebView(for: selectedTab.id, in: windowState.id))
        for tab in [loadingTab, audioTab, pipTab, pdfTab, pageVetoTab, fileTab, protectedTab] {
            XCTAssertTrue(
                coordinator.getWebView(for: tab.id, in: windowState.id) === webViewsByTabID[tab.id],
                "Expected vetoed tab to keep its WebView: \(tab.url.absoluteString)"
            )
            XCTAssertFalse(tab.isSuspended)
        }
        XCTAssertTrue(coordinator.getWebView(for: eligibleTab.id, in: windowState.id) === webViewsByTabID[eligibleTab.id])
        XCTAssertFalse(eligibleTab.isSuspended)
        XCTAssertTrue(browserManager.tabSuspensionService.proactiveTimerTabIDsForTesting.contains(eligibleTab.id))

        coordinator.finishHistorySwipeProtection(
            tabId: protectedTab.id,
            webView: webViewsByTabID[protectedTab.id],
            currentURL: protectedTab.url,
            currentHistoryItem: nil
        )
        _ = settings
    }

    func testHiddenCleanupPreservesActiveSplitVisibleTabsAndLeavesHiddenDeactivationToTimer() throws {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let settings = installMemoryMode(.maximum, on: browserManager)
        let (_, windowState) = makeWindowContext(browserManager: browserManager)

        let leftTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/maximum-split-left",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let rightTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/maximum-split-right",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let hiddenTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/maximum-split-hidden",
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
        let leftWebView = try XCTUnwrap(coordinator.getWebView(for: leftTab.id, in: windowState.id))
        let rightWebView = try XCTUnwrap(coordinator.getWebView(for: rightTab.id, in: windowState.id))
        let hiddenWebView = try XCTUnwrap(coordinator.getOrCreateWebView(for: hiddenTab, in: windowState.id))

        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)

        XCTAssertTrue(coordinator.getWebView(for: leftTab.id, in: windowState.id) === leftWebView)
        XCTAssertTrue(coordinator.getWebView(for: rightTab.id, in: windowState.id) === rightWebView)
        XCTAssertFalse(leftTab.isSuspended)
        XCTAssertFalse(rightTab.isSuspended)
        XCTAssertTrue(coordinator.getWebView(for: hiddenTab.id, in: windowState.id) === hiddenWebView)
        XCTAssertFalse(hiddenTab.isSuspended)
        XCTAssertTrue(browserManager.tabSuspensionService.proactiveTimerTabIDsForTesting.contains(hiddenTab.id))
        _ = settings
    }

    func testPrepareVisibleWebViewsDoesNotUseWarmHiddenBudgetAsProactivePolicy() {
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

        XCTAssertEqual(coordinator.windowID(containing: firstWebView), windowState.id)
        XCTAssertEqual(coordinator.windowID(containing: secondWebView), windowState.id)
        XCTAssertEqual(coordinator.windowID(containing: thirdWebView), windowState.id)
        XCTAssertNotNil(coordinator.getWebView(for: firstTab.id, in: windowState.id))
        XCTAssertNotNil(coordinator.getWebView(for: secondTab.id, in: windowState.id))
        XCTAssertNotNil(coordinator.getWebView(for: thirdTab.id, in: windowState.id))
    }

    func testPrepareVisibleWebViewsDoesNotUseWarmHiddenBudgetForSplitHiddenTabs() {
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
        let hiddenWebView = try! XCTUnwrap(coordinator.getOrCreateWebView(
            for: hiddenTab,
            in: windowState.id
        ))
        let secondHiddenWebView = try! XCTUnwrap(coordinator.getOrCreateWebView(
            for: secondHiddenTab,
            in: windowState.id
        ))

        _ = coordinator.prepareVisibleWebViews(for: windowState, browserManager: browserManager)

        XCTAssertTrue(coordinator.getWebView(for: leftTab.id, in: windowState.id) === leftWebView)
        XCTAssertTrue(coordinator.getWebView(for: rightTab.id, in: windowState.id) === rightWebView)
        XCTAssertTrue(coordinator.getWebView(for: hiddenTab.id, in: windowState.id) === hiddenWebView)
        XCTAssertTrue(
            coordinator.getWebView(for: secondHiddenTab.id, in: windowState.id) === secondHiddenWebView
        )
        XCTAssertEqual(coordinator.windowID(containing: hiddenWebView), windowState.id)
        XCTAssertEqual(coordinator.windowID(containing: secondHiddenWebView), windowState.id)
    }

    func testPrepareVisibleWebViewsCleansHiddenCloneWhenTabIsVisibleInAnotherWindow() {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        browserManager.webViewCoordinator = coordinator
        let (registry, firstWindow) = makeWindowContext(browserManager: browserManager)

        let secondWindow = BrowserWindowState()
        secondWindow.tabManager = browserManager.tabManager
        secondWindow.currentSpaceId = firstWindow.currentSpaceId
        registry.register(secondWindow)

        let sharedTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/shared",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let soleHiddenTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/sole-hidden",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let currentTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/current",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        setCurrentTab(sharedTab, in: firstWindow)
        _ = coordinator.prepareVisibleWebViews(for: firstWindow, browserManager: browserManager)

        setCurrentTab(sharedTab, in: secondWindow)
        _ = coordinator.prepareVisibleWebViews(for: secondWindow, browserManager: browserManager)
        let sharedCloneInSecondWindow = try! XCTUnwrap(
            coordinator.getWebView(for: sharedTab.id, in: secondWindow.id)
        )

        setCurrentTab(soleHiddenTab, in: firstWindow)
        _ = coordinator.prepareVisibleWebViews(for: firstWindow, browserManager: browserManager)

        setCurrentTab(currentTab, in: firstWindow)
        _ = coordinator.prepareVisibleWebViews(for: firstWindow, browserManager: browserManager)

        XCTAssertNil(coordinator.getWebView(for: sharedTab.id, in: firstWindow.id))
        XCTAssertTrue(
            coordinator.getWebView(for: sharedTab.id, in: secondWindow.id) === sharedCloneInSecondWindow
        )
        XCTAssertNotNil(coordinator.getWebView(for: soleHiddenTab.id, in: firstWindow.id))
        XCTAssertNotNil(coordinator.getWebView(for: currentTab.id, in: firstWindow.id))
    }

    private func makeWindow(
        contentRect: NSRect = NSRect(x: 0, y: 0, width: 320, height: 240)
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        location: NSPoint,
        windowNumber: Int
    ) -> NSEvent {
        if [.cursorUpdate, .mouseEntered, .mouseExited].contains(type) {
            guard let event = NSEvent.enterExitEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil
            ) else {
                fatalError("Failed to create cursor event for test.")
            }
            return event
        }

        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            fatalError("Failed to create mouse event for test.")
        }
        return event
    }

    private func installMemoryMode(
        _ mode: SumiMemoryMode,
        on browserManager: BrowserManager
    ) -> SumiSettingsService {
        let defaultsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: defaultsHarness.defaults)
        settings.memoryMode = mode
        browserManager.sumiSettings = settings
        browserManager.tabManager.sumiSettings = settings
        return settings
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

    private func assertNormalTabWebView(
        _ webView: WKWebView,
        for tab: Tab,
        browserManager: BrowserManager,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let profile = tab.resolveProfile() ?? browserManager.currentProfile

        XCTAssertTrue(
            webView.configuration.processPool === BrowserConfiguration.shared.normalTabProcessPool,
            file: file,
            line: line
        )
        XCTAssertTrue(
            webView.configuration.websiteDataStore === profile?.dataStore,
            file: file,
            line: line
        )

        guard let provider = webView.configuration.userContentController.sumiNormalTabUserScriptsProvider else {
            XCTFail("Expected normal-tab user scripts provider", file: file, line: line)
            return
        }
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")
        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"), file: file, line: line)
        XCTAssertTrue(sources.contains("sumiIdentity_\(tab.id.uuidString)"), file: file, line: line)
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"), file: file, line: line)
        XCTAssertTrue(sources.contains("__sumiTabSuspension"), file: file, line: line)
    }
}
