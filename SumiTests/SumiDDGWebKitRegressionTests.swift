import AppKit
@testable import Sumi
import WebKit
import XCTest

@MainActor
final class SumiDDGWebKitRegressionTests: XCTestCase {
    func testFindChromeFocusedTextFieldUsesIBeamFieldEditor() throws {
        let viewController = FindInPageViewController.create()
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: FindInPageChromeLayout.panelWidth,
                height: FindInPageChromeLayout.panelHeight
            ),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = viewController.view
        defer {
            window.close()
            window.contentView = nil
        }

        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(viewController.textField))
        viewController.textField.selectText(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let editor = try XCTUnwrap(viewController.textField.currentEditor())
        XCTAssertIdentical(window.firstResponder, editor)
        XCTAssertTrue(editor.isFieldEditor)
        XCTAssertTrue(String(describing: type(of: editor)).contains("FindInPageFieldEditor"))
    }

    func testFocusableWebViewDoesNotDuplicateWebKitMouseTrackingObserverArea() {
        let webView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            configuration: WKWebViewConfiguration()
        )
        let owner = FakeWebKitMouseTrackingObserver()
        let trackingArea = NSTrackingArea(
            rect: webView.bounds,
            options: [.activeAlways, .mouseMoved],
            owner: owner,
            userInfo: nil
        )

        webView.addTrackingArea(trackingArea)
        webView.addTrackingArea(trackingArea)

        XCTAssertEqual(webView.trackingAreas.filter { $0 === trackingArea }.count, 1)
    }

    func testFocusableWebViewPrivateFindResumesDelegateCallback() async {
        let webView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: WKWebViewConfiguration()
        )
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        await loadHTML(
            """
            <!doctype html>
            <html>
            <body>
                <p>needle</p>
                <p>Needle</p>
                <p>needle</p>
            </body>
            </html>
            """,
            into: webView
        )

        let resultRecorder = FindResultRecorder()
        let didFind = expectation(description: "private find delegate callback resumed")
        Task { @MainActor in
            resultRecorder.result = await webView.find(
                "needle",
                with: [.caseInsensitive, .wrapAround, .showFindIndicator, .showOverlay],
                maxCount: 1000
            )
            didFind.fulfill()
        }

        await fulfillment(of: [didFind], timeout: 3)
        XCTAssertEqual(resultRecorder.result, .found(matches: 3))
    }

    func testImmediateVisualHandoffHandlerIsWindowScopedAndRemovedWithContainer() {
        let coordinator = WebViewCoordinator()
        let windowID = UUID()
        var handoffCount = 0

        coordinator.setImmediateVisualHandoffHandler({
            handoffCount += 1
            return true
        }, for: windowID)

        XCTAssertTrue(coordinator.performImmediateVisualHandoffIfPossible(in: windowID))
        XCTAssertEqual(handoffCount, 1)

        coordinator.removeCompositorContainerView(for: windowID)

        XCTAssertFalse(coordinator.performImmediateVisualHandoffIfPossible(in: windowID))
        XCTAssertEqual(handoffCount, 1)
    }

    func testCompositorHandoffStatePrunesStaleContainerAndHandlerTogether() {
        let handoffState = WebViewCompositorHandoffState()
        let windowID = UUID()
        var container: NSView? = NSView()
        var handoffCount = 0

        handoffState.setContainerView(container, for: windowID)
        handoffState.setImmediateVisualHandoffHandler({
            handoffCount += 1
            return true
        }, for: windowID)

        XCTAssertNotNil(handoffState.containerView(for: windowID))
        XCTAssertTrue(handoffState.performImmediateVisualHandoffIfPossible(in: windowID))
        XCTAssertEqual(handoffCount, 1)

        container = nil

        XCTAssertNil(handoffState.containerView(for: windowID))
        XCTAssertFalse(handoffState.performImmediateVisualHandoffIfPossible(in: windowID))
        XCTAssertEqual(handoffCount, 1)
    }

    func testCompositorHandoffStatePromotedHostCompletionRunsOnceAfterMatchingTake() throws {
        let handoffState = WebViewCompositorHandoffState()
        let tab = Tab(url: try XCTUnwrap(URL(string: "https://example.com")))
        let windowID = UUID()
        let webView = WKWebView()
        let host = SumiWebViewContainerView(tab: tab, webView: webView)
        var completionCount = 0

        handoffState.registerPromotedHost(
            host,
            for: tab.id,
            in: windowID,
            attachmentCompletion: {
                completionCount += 1
            }
        )

        XCTAssertNil(handoffState.takePromotedHost(
            for: tab.id,
            in: windowID,
            expectedWebView: WKWebView()
        ))

        let takenHost = handoffState.takePromotedHost(
            for: tab.id,
            in: windowID,
            expectedWebView: webView
        )
        XCTAssertIdentical(takenHost, host)
        XCTAssertNil(handoffState.takePromotedHost(
            for: tab.id,
            in: windowID,
            expectedWebView: webView
        ))

        handoffState.completePromotedHostAttachment(for: tab.id, in: windowID)
        handoffState.completePromotedHostAttachment(for: tab.id, in: windowID)

        XCTAssertEqual(completionCount, 1)
    }

    func testVisualHandoffProtectionIsReleasedExplicitly() {
        let coordinator = WebViewCoordinator()
        let webView = WKWebView()

        coordinator.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(coordinator.isWebViewProtectedFromCompositorMutation(webView))

        coordinator.finishVisualHandoffProtection(for: webView)
        XCTAssertFalse(coordinator.isWebViewProtectedFromCompositorMutation(webView))
    }

    func testWebsiteDisplayStateActiveSplitGroupRequiresCurrentTabMembership() throws {
        let current = UUID()
        let secondary = UUID()
        let outside = UUID()
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [current, secondary],
            layoutKind: .vertical
        ))

        let activeState = WebsiteDisplayState(
            splitGroup: group,
            currentId: current,
            compositorVersion: 1,
            currentTabUnloaded: false,
            visibleTabIds: [current, secondary],
            isSplitDropCaptureActive: false
        )
        XCTAssertEqual(activeState.activeSplitGroup?.id, group.id)

        let outsideState = WebsiteDisplayState(
            splitGroup: group,
            currentId: outside,
            compositorVersion: 1,
            currentTabUnloaded: false,
            visibleTabIds: [outside],
            isSplitDropCaptureActive: false
        )
        XCTAssertNil(outsideState.activeSplitGroup)

        let nilCurrentState = WebsiteDisplayState(
            splitGroup: group,
            currentId: nil,
            compositorVersion: 1,
            currentTabUnloaded: true,
            visibleTabIds: [],
            isSplitDropCaptureActive: false
        )
        XCTAssertNil(nilCurrentState.activeSplitGroup)
    }

    func testWindowWebContentUsesBrowserContextBoundary() {
        let browserContext = CompositorBrowserContextStub()
        let windowState = BrowserWindowState()
        let webViewCoordinator = WebViewCoordinator()

        let wrapper = TabCompositorWrapper(
            browserContext: browserContext,
            webViewCoordinator: webViewCoordinator,
            hoveredLink: .constant(nil),
            splitGroup: nil,
            isSplitDropCaptureActive: false,
            chromeGeometry: BrowserChromeGeometry(),
            windowState: windowState,
            contentBackgroundColor: .white
        )

        XCTAssertFalse(wrapper.isSplitDropCaptureActive)
    }

    func testCloneWebViewPrimaryWindowSelectionUsesStableRegistryFallback() {
        let stableFallback = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let laterFallback = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        XCTAssertEqual(
            WebViewCreationPlanningOwner.primaryWindowIdForClone(
                otherWindowIds: [laterFallback, stableFallback]
            ),
            stableFallback
        )
    }

    func testDeferredProtectedCommandBufferCollapsesDuplicateKeysInPlace() {
        var buffer = DeferredProtectedCommandBuffer()
        let tabID = UUID()
        let firstPreferredWindowID = UUID()
        let latestPreferredWindowID = UUID()

        XCTAssertEnqueueOutcome(
            buffer.enqueue(.rebuildLiveWebViews(
                tabID: tabID,
                preferredPrimaryWindowID: firstPreferredWindowID
            )),
            is: .enqueued
        )
        XCTAssertEnqueueOutcome(buffer.enqueue(.cleanupAllWebViews), is: .enqueued)
        XCTAssertEnqueueOutcome(
            buffer.enqueue(.rebuildLiveWebViews(
                tabID: tabID,
                preferredPrimaryWindowID: latestPreferredWindowID
            )),
            is: .collapsed
        )
        XCTAssertEqual(buffer.count, 2)

        let drained = buffer.drain()
        XCTAssertEqual(drained.count, 2)
        guard case let .rebuildLiveWebViews(drainedTabID, drainedPreferredWindowID) = drained[0],
              case .cleanupAllWebViews = drained[1]
        else {
            return XCTFail("Expected duplicate command replacement to keep original FIFO slot")
        }
        XCTAssertEqual(drainedTabID, tabID)
        XCTAssertEqual(drainedPreferredWindowID, latestPreferredWindowID)
    }

    func testDeferredProtectedCommandBufferDropsAtCapacityWithoutMutatingExistingCommands() {
        var buffer = DeferredProtectedCommandBuffer()
        let commandIDs = (0..<DeferredProtectedCommandBuffer.maxCommands).map { _ in UUID() }

        for commandID in commandIDs {
            XCTAssertEnqueueOutcome(
                buffer.enqueue(.removeAllWebViews(tabID: commandID)),
                is: .enqueued
            )
        }
        XCTAssertEqual(buffer.count, DeferredProtectedCommandBuffer.maxCommands)

        let droppedTabID = UUID()
        XCTAssertEnqueueOutcome(
            buffer.enqueue(.removeAllWebViews(tabID: droppedTabID)),
            is: .droppedAtCapacity
        )
        XCTAssertEqual(buffer.count, DeferredProtectedCommandBuffer.maxCommands)

        let drained = buffer.drain()
        XCTAssertEqual(drained.count, DeferredProtectedCommandBuffer.maxCommands)
        for (command, expectedTabID) in zip(drained, commandIDs) {
            guard case let .removeAllWebViews(drainedTabID) = command else {
                return XCTFail("Expected capacity drop to leave queued commands unchanged")
            }
            XCTAssertEqual(drainedTabID, expectedTabID)
        }
    }

    func testDeferredProtectedCommandBufferPruneReturnsDroppedCommandsAndKeepsSurvivorsInOrder() {
        var buffer = DeferredProtectedCommandBuffer()
        let firstTabID = UUID()
        let droppedWindowID = UUID()
        let lastTabID = UUID()

        XCTAssertEnqueueOutcome(buffer.enqueue(.removeAllWebViews(tabID: firstTabID)), is: .enqueued)
        XCTAssertEnqueueOutcome(buffer.enqueue(.cleanupWindow(windowID: droppedWindowID)), is: .enqueued)
        XCTAssertEnqueueOutcome(buffer.enqueue(.rebuildLiveWebViews(
            tabID: lastTabID,
            preferredPrimaryWindowID: nil
        )), is: .enqueued)

        let droppedCommands = buffer.prune { command in
            if case .cleanupWindow = command { return true }
            return false
        }

        XCTAssertEqual(droppedCommands.count, 1)
        guard case let .cleanupWindow(drainedDroppedWindowID) = droppedCommands[0] else {
            return XCTFail("Expected prune to return the dropped command")
        }
        XCTAssertEqual(drainedDroppedWindowID, droppedWindowID)

        let survivors = buffer.drain()
        XCTAssertEqual(survivors.count, 2)
        guard case let .removeAllWebViews(drainedFirstTabID) = survivors[0],
              case let .rebuildLiveWebViews(drainedLastTabID, drainedPreferredWindowID) = survivors[1]
        else {
            return XCTFail("Expected prune to keep survivors in FIFO order")
        }
        XCTAssertEqual(drainedFirstTabID, firstTabID)
        XCTAssertEqual(drainedLastTabID, lastTabID)
        XCTAssertNil(drainedPreferredWindowID)
    }

    func testDestructiveCleanupPreparationOwnerTracksWebViewIdentity() {
        let firstWebView = WKWebView()
        let secondWebView = WKWebView()
        let owner = WebViewDestructiveCleanupPreparationOwner()

        XCTAssertFalse(owner.isSuppressingNavigation(on: firstWebView))
        XCTAssertFalse(owner.isSuppressingNavigation(on: secondWebView))

        owner.beginNavigationSuppression(on: firstWebView)
        XCTAssertTrue(owner.isSuppressingNavigation(on: firstWebView))
        XCTAssertFalse(owner.isSuppressingNavigation(on: secondWebView))

        owner.finishNavigationSuppression(on: firstWebView)
        XCTAssertFalse(owner.isSuppressingNavigation(on: firstWebView))

        owner.beginNavigationSuppression(on: firstWebView)
        owner.finishNavigationSuppression(webViewID: ObjectIdentifier(firstWebView))
        XCTAssertFalse(owner.isSuppressingNavigation(on: firstWebView))
    }

    func testNativeSplitTreeViewRestoresStoredSizesAndReportsUserResize() throws {
        let splitView = NativeSplitTreeView(axis: .row, path: [1, 0], sizes: [0.25, 0.75])
        let leftPane = NSView()
        let rightPane = NSView()
        var reportedResize: (path: [Int], sizes: [Double])?

        splitView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        splitView.addSubview(leftPane)
        splitView.addSubview(rightPane)
        splitView.resizeHandler = { path, sizes in
            reportedResize = (path, sizes)
        }

        splitView.layoutSubtreeIfNeeded()

        XCTAssertNil(reportedResize)
        XCTAssertEqual(leftPane.frame.width, 100, accuracy: 4)
        XCTAssertEqual(rightPane.frame.width, 300, accuracy: 4)

        reportedResize = nil
        splitView.setPosition(280, ofDividerAt: 0)
        if reportedResize == nil {
            splitView.splitViewDidResizeSubviews(
                Notification(name: NSSplitView.didResizeSubviewsNotification, object: splitView)
            )
        }

        let resize = try XCTUnwrap(reportedResize)
        XCTAssertEqual(resize.path, [1, 0])
        XCTAssertEqual(resize.sizes.reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(resize.sizes[0], 0.60)
        XCTAssertLessThan(resize.sizes[1], 0.40)
    }

    @MainActor
    private final class CompositorBrowserContextStub: WindowWebContentBrowserContext {
        let sidebarDragState = SidebarDragState()

        func currentTab(for _: BrowserWindowState) -> Tab? {
            nil
        }

        func tab(for _: UUID) -> Tab? {
            nil
        }

        func splitGroup(for _: UUID) -> SplitGroup? {
            nil
        }

        func schedulePrepareVisibleWebViews(for _: BrowserWindowState) { /* no-op */ }

        func enqueueWindowMutationDuringHistorySwipe(
            _: HistorySwipeDeferredWindowMutationKind,
            for _: BrowserWindowState
        ) { /* no-op */ }

        func removeSplitGroup(id _: UUID) { /* no-op */ }

        func updateSplitLayoutSizes(
            groupId _: UUID,
            path _: [Int],
            sizes _: [Double],
            for _: UUID
        ) { /* no-op */ }

        func configureSplitDropCapture(_: SplitDropCaptureView, windowId _: UUID) { /* no-op */ }

        func configureSplitControls(
            _: SplitPaneControlsView,
            tab _: Tab,
            windowState _: BrowserWindowState
        ) { /* no-op */ }
    }

    private func XCTAssertEnqueueOutcome(
        _ actual: DeferredProtectedCommandEnqueueOutcome,
        is expected: DeferredProtectedCommandEnqueueOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.enqueued, .enqueued),
             (.collapsed, .collapsed),
             (.droppedAtCapacity, .droppedAtCapacity):
            break
        default:
            XCTFail("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }

    private func loadHTML(_ html: String, into webView: WKWebView) async {
        let didFinish = expectation(description: "find test page loaded")
        let delegate = FindNavigationDelegateBox {
            didFinish.fulfill()
        }

        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com"))
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil
    }
}

@MainActor
private final class FindResultRecorder {
    var result: FocusableWKWebView.FindResult?
}

private final class FindNavigationDelegateBox: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) { // swiftlint:disable:this implicitly_unwrapped_optional
        onFinish()
    }
}

private final class FakeWebKitMouseTrackingObserver: NSObject {
    override var className: String {
        "WKMouseTrackingObserver"
    }
}
