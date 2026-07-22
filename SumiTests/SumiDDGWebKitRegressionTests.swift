import AppKit
@testable import Sumi
import SumiDomain
import SumiWebRuntime
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
        let graph = makeTestWebViewRuntimeGraph()
        let windowID = UUID()
        let container = NSView()
        var handoffCount = 0

        let registration = graph.compositorRuntime.registerContainer(
            container,
            for: windowID,
            immediateVisualHandoffHandler: {
                handoffCount += 1
                return true
            }
        )

        XCTAssertTrue(
            graph.compositorRuntime.performImmediateVisualHandoffIfPossible(
                in: windowID
            )
        )
        XCTAssertEqual(handoffCount, 1)

        XCTAssertTrue(graph.compositorRuntime.removeContainer(registration))

        XCTAssertFalse(
            graph.compositorRuntime.performImmediateVisualHandoffIfPossible(
                in: windowID
            )
        )
        XCTAssertEqual(handoffCount, 1)
        withExtendedLifetime(container) {}
    }

    func testStaleCompositorRegistrationCannotTearDownReplacementController() {
        let graph = makeTestWebViewRuntimeGraph()
        let windowID = UUID()
        let staleContainer = NSView()
        let replacementContainer = NSView()
        var replacementHandoffCount = 0
        var fullscreenCloseCount = 0
        let staleRegistration = graph.compositorRuntime.registerContainer(
            staleContainer,
            for: windowID
        )
        let replacementRegistration = graph.compositorRuntime.registerContainer(
            replacementContainer,
            for: windowID,
            immediateVisualHandoffHandler: {
                replacementHandoffCount += 1
                return true
            }
        )

        XCTAssertFalse(graph.compositorRuntime.tearDownContainer(
            staleRegistration,
            teardown: { fullscreenCloseCount += 1 }
        ))
        XCTAssertEqual(fullscreenCloseCount, 0)
        XCTAssertIdentical(
            graph.compositorRuntime.containerView(for: windowID),
            replacementContainer
        )
        XCTAssertTrue(
            graph.compositorRuntime.performImmediateVisualHandoffIfPossible(
                in: windowID
            )
        )
        XCTAssertEqual(replacementHandoffCount, 1)
        XCTAssertTrue(graph.compositorRuntime.tearDownContainer(
            replacementRegistration,
            teardown: { fullscreenCloseCount += 1 }
        ))
        XCTAssertEqual(fullscreenCloseCount, 1)
        XCTAssertNil(graph.compositorRuntime.containerView(for: windowID))
        withExtendedLifetime((staleContainer, replacementContainer)) {}
    }

    func testCompositorMutationGateRejectsQueuedWorkAfterSupersessionAndInvalidation() {
        let graph = makeTestWebViewRuntimeGraph()
        let windowID = UUID()
        let staleContainer = NSView()
        let replacementContainer = NSView()
        let staleRegistration = graph.compositorRuntime.registerContainer(
            staleContainer,
            for: windowID
        )
        let staleGate = WindowWebContentCompositorMutationGate(
            isCurrentRegistration: graph.compositorRuntime.owns
        )
        staleGate.activate(staleRegistration)
        var staleHostMutationCount = 0
        let queuedStaleHostMutation = {
            guard staleGate.owns(staleRegistration) else { return false }
            staleHostMutationCount += 1
            return true
        }

        let replacementRegistration = graph.compositorRuntime.registerContainer(
            replacementContainer,
            for: windowID
        )

        XCTAssertFalse(queuedStaleHostMutation())
        XCTAssertEqual(staleHostMutationCount, 0)

        let replacementGate = WindowWebContentCompositorMutationGate(
            isCurrentRegistration: graph.compositorRuntime.owns
        )
        replacementGate.activate(replacementRegistration)
        var invalidatedApplyCount = 0
        let queuedInvalidatedApply = {
            guard replacementGate.owns(replacementRegistration) else { return false }
            invalidatedApplyCount += 1
            return true
        }
        XCTAssertEqual(replacementGate.invalidate(), replacementRegistration)

        XCTAssertFalse(queuedInvalidatedApply())
        XCTAssertEqual(invalidatedApplyCount, 0)
        XCTAssertTrue(
            graph.compositorRuntime.removeContainer(replacementRegistration)
        )
        withExtendedLifetime((staleContainer, replacementContainer)) {}
    }

    func testCompositorHandoffStatePrunesStaleContainerAndHandlerTogether() {
        let handoffState = WebViewCompositorHandoffState()
        let windowID = UUID()
        var container: NSView? = NSView()
        var handoffCount = 0

        handoffState.registerContainerView(
            container!,
            for: windowID,
            immediateVisualHandoffHandler: {
                handoffCount += 1
                return true
            }
        )

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
        let host = SumiWebViewContainerView(tabID: tab.id, webView: webView)
        let container = NSView()
        var outcomes: [PromotedHostAttachmentOutcome] = []
        let registration = handoffState.registerContainerView(container, for: windowID)

        XCTAssertTrue(handoffState.registerPromotedHost(
            host,
            for: tab.id,
            in: windowID,
            attachmentCompletion: { outcomes.append($0) }
        ))

        XCTAssertNil(handoffState.takePromotedHost(
            for: tab.id,
            in: windowID,
            containerRegistration: registration,
            expectedWebView: WKWebView()
        ))

        let takenHost = handoffState.takePromotedHost(
            for: tab.id,
            in: windowID,
            containerRegistration: registration,
            expectedWebView: webView
        )
        XCTAssertIdentical(takenHost, host)
        XCTAssertNil(handoffState.takePromotedHost(
            for: tab.id,
            in: windowID,
            containerRegistration: registration,
            expectedWebView: webView
        ))

        handoffState.completePromotedHostAttachment(
            for: tab.id,
            in: windowID,
            containerRegistration: registration
        )
        handoffState.completePromotedHostAttachment(
            for: tab.id,
            in: windowID,
            containerRegistration: registration
        )

        XCTAssertEqual(outcomes, [.attached])
        withExtendedLifetime(container) {}
    }

    func testVisualHandoffProtectionIsReleasedExplicitly() throws {
        let graph = makeTestWebViewRuntimeGraph()
        let webView = WKWebView()
        let container = NSView()
        let registration = graph.compositorRuntime.registerContainer(
            container,
            for: UUID()
        )

        let protectionLease = try XCTUnwrap(
            graph.protectionRuntime.beginVisualHandoff(
            for: webView,
            containerRegistration: registration
            )
        )
        XCTAssertTrue(graph.protectionRuntime.isProtected(webView))

        graph.protectionRuntime.finishVisualHandoff(protectionLease)
        XCTAssertFalse(graph.protectionRuntime.isProtected(webView))
        withExtendedLifetime(container) {}
    }

    func testWebsiteDisplayStateActivatesOnlyTheWindowSelectedSplitPane() throws {
        let current = UUID()
        let secondary = UUID()
        let outside = UUID()
        let group = try XCTUnwrap(SumiDomain.SplitGroup.make(
            members: [.regularTab(current), .regularTab(secondary)],
            layoutKind: .vertical
        ))
        let selection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(current)
        )
        let presentation = try XCTUnwrap(WindowSplitPresentation(
            windowID: UUID(),
            group: group,
            selection: selection,
            liveTabIDByMemberID: [
                .regularTab(current): current,
                .regularTab(secondary): secondary,
            ]
        ))

        let activeState = WebsiteDisplayState(
            splitPresentation: presentation,
            currentId: current,
            compositorVersion: 1,
            currentTabUnloaded: false,
            isSplitDropCaptureActive: false
        )
        XCTAssertEqual(activeState.activeSplitPresentation?.groupID, group.id)
        XCTAssertEqual(activeState.visibleTabIDs, [current, secondary])

        let outsideState = WebsiteDisplayState(
            splitPresentation: presentation,
            currentId: outside,
            compositorVersion: 1,
            currentTabUnloaded: false,
            isSplitDropCaptureActive: false
        )
        XCTAssertNil(outsideState.activeSplitPresentation)
        XCTAssertEqual(outsideState.visibleTabIDs, [outside])

        let nilCurrentState = WebsiteDisplayState(
            splitPresentation: presentation,
            currentId: nil,
            compositorVersion: 1,
            currentTabUnloaded: true,
            isSplitDropCaptureActive: false
        )
        XCTAssertNil(nilCurrentState.activeSplitPresentation)
        XCTAssertTrue(nilCurrentState.visibleTabIDs.isEmpty)
    }

    func testWindowWebContentUsesBrowserContextBoundary() {
        let browserContext = CompositorBrowserContextStub()
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let webViewRuntime = makeTestWebViewRuntimeGraph()

        let wrapper = TabCompositorWrapper(
            browserContext: browserContext,
            resolveDragTab: {
                browserManager.sidebarDragRouter
                    .resolveDragTab(for: $0)
            },
            splitQuery: browserManager.splitWindowContext.query,
            splitPreviews: browserManager.splitWindowContext.previews,
            splitLayout: browserManager.splitWindowContext.layout,
            splitDrops: browserManager.splitWindowContext.drops,
            splitDropTargets: browserManager.splitWindowContext.dropTargets,
            sidebarDragState: browserContext.sidebarDragState,
            webViewOwnershipQuery: webViewRuntime.ownershipQuery,
            trackedWebViewAdmission: webViewRuntime.trackedWebViewAdmission,
            webViewCompositorRuntime: webViewRuntime.compositorRuntime,
            webViewProtectionRuntime: webViewRuntime.protectionRuntime,
            hoveredLink: .constant(nil),
            splitPresentation: nil,
            isSplitDropCaptureActive: false,
            chromeGeometry: BrowserChromeGeometry(),
            windowState: windowState,
            contentBackgroundColor: .white
        )

        XCTAssertFalse(wrapper.isSplitDropCaptureActive)
    }

    func testPresentationPlannerUsesWindowLiveIDsInsteadOfCanonicalShortcutIDs() throws {
        let firstLiveShortcutTab = Tab(
            url: try XCTUnwrap(URL(string: "https://first-shortcut.example")),
            loadsCachedFaviconOnInit: false
        )
        let secondLiveShortcutTab = Tab(
            url: try XCTUnwrap(URL(string: "https://shortcut.example")),
            loadsCachedFaviconOnInit: false
        )
        let firstPinID = UUID()
        let secondPinID = UUID()
        let group = try XCTUnwrap(SumiDomain.SplitGroup.make(
            members: [
                .shortcutPin(firstPinID),
                .shortcutPin(secondPinID),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: UUID(),
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        let windowState = BrowserWindowState()
        let presentation = try XCTUnwrap(WindowSplitPresentation(
            windowID: windowState.id,
            group: group,
            selection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .shortcutPin(secondPinID)
            ),
            liveTabIDByMemberID: [
                .shortcutPin(firstPinID): firstLiveShortcutTab.id,
                .shortcutPin(secondPinID): secondLiveShortcutTab.id,
            ]
        ))
        let browserContext = CompositorBrowserContextStub()
        browserContext.tabsByID = [
            firstLiveShortcutTab.id: firstLiveShortcutTab,
            secondLiveShortcutTab.id: secondLiveShortcutTab,
        ]
        let browserManager = BrowserManager()
        let graph = makeTestWebViewRuntimeGraph()
        let container = WindowWebContentSplitHostLayoutView(
            splitLayout: browserManager.splitWindowContext.layout,
            splitDrops: browserManager.splitWindowContext.drops,
            splitDropTargets: browserManager.splitWindowContext.dropTargets,
            splitPreviews: browserManager.splitWindowContext.previews,
            sidebarDragState: browserContext.sidebarDragState,
            windowState: windowState,
            resolveDragTab: {
                browserManager.sidebarDragRouter
                    .resolveDragTab(for: $0)
            },
            chromeGeometry: BrowserChromeGeometry()
        )
        let planner = WindowWebContentPresentationPlanner(
            browserContext: browserContext,
            splitQuery: browserManager.splitWindowContext.query,
            windowState: windowState,
            containerView: container,
            hostRegistry: WindowWebContentHostRegistry(),
            protectionRuntime: graph.protectionRuntime
        )
        let displayState = WebsiteDisplayState(
            splitPresentation: presentation,
            currentId: secondLiveShortcutTab.id,
            compositorVersion: 0,
            currentTabUnloaded: false,
            isSplitDropCaptureActive: false
        )

        guard case .split(let resolvedPresentation, let tabs) = planner
            .presentationDecision(
                for: displayState,
                currentTab: secondLiveShortcutTab
            ) else {
            return XCTFail("Expected a split presentation")
        }
        XCTAssertEqual(resolvedPresentation, presentation)
        XCTAssertEqual(
            tabs.map(\.id),
            [firstLiveShortcutTab.id, secondLiveShortcutTab.id]
        )
        XCTAssertTrue(Set(tabs.map(\.id)).isDisjoint(
            with: [firstPinID, secondPinID]
        ))
    }

    func testWindowWebContentHoverSessionReconcilesExactWebViewAndRejectsStaleRegistration() async throws {
        let webViewRuntime = makeTestWebViewRuntimeGraph()
        let windowID = UUID()
        let firstContainer = NSView()
        let firstRegistration = webViewRuntime.compositorRuntime.registerContainer(
            firstContainer,
            for: windowID
        )
        let mutationGate = WindowWebContentCompositorMutationGate(
            isCurrentRegistration: webViewRuntime.compositorRuntime.owns
        )
        mutationGate.activate(firstRegistration)
        let session = WindowWebContentHoverSession(mutationGate: mutationGate)
        let firstWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        let replacementWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        var deliveredLinks: [String] = []

        session.reconcile(
            webViews: [firstWebView],
            registration: firstRegistration,
            deliver: { link in
                if let link { deliveredLinks.append(link) }
            }
        )
        firstWebView.hoveredLink.update("https://first.example/link")
        await drainMainQueue()
        XCTAssertEqual(deliveredLinks, ["https://first.example/link"])

        session.reconcile(
            webViews: [replacementWebView],
            registration: firstRegistration,
            deliver: { link in
                if let link { deliveredLinks.append(link) }
            }
        )
        firstWebView.hoveredLink.update("https://first.example/retired")
        replacementWebView.hoveredLink.update("https://replacement.example/link")
        await drainMainQueue()
        XCTAssertEqual(
            deliveredLinks,
            ["https://first.example/link", "https://replacement.example/link"]
        )

        let replacementContainer = NSView()
        _ = webViewRuntime.compositorRuntime.registerContainer(
            replacementContainer,
            for: windowID
        )
        replacementWebView.hoveredLink.update("https://replacement.example/stale")
        await drainMainQueue()
        XCTAssertEqual(
            deliveredLinks,
            ["https://first.example/link", "https://replacement.example/link"]
        )

        session.invalidate()
        withExtendedLifetime((firstContainer, replacementContainer)) {}
    }

    func testSameTabPhysicalHoverSessionsRemainIndependentWhenOneWindowTearsDown() async {
        let webViewRuntime = makeTestWebViewRuntimeGraph()
        let tab = Tab(name: "Cloned")
        let firstWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        let secondWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        firstWebView.owningTab = tab
        secondWebView.owningTab = tab

        let firstContainer = NSView()
        let firstRegistration = webViewRuntime.compositorRuntime.registerContainer(
            firstContainer,
            for: UUID()
        )
        let firstGate = WindowWebContentCompositorMutationGate(
            isCurrentRegistration: webViewRuntime.compositorRuntime.owns
        )
        firstGate.activate(firstRegistration)
        let firstSession = WindowWebContentHoverSession(mutationGate: firstGate)

        let secondContainer = NSView()
        let secondRegistration = webViewRuntime.compositorRuntime.registerContainer(
            secondContainer,
            for: UUID()
        )
        let secondGate = WindowWebContentCompositorMutationGate(
            isCurrentRegistration: webViewRuntime.compositorRuntime.owns
        )
        secondGate.activate(secondRegistration)
        let secondSession = WindowWebContentHoverSession(mutationGate: secondGate)
        var firstLinks: [String] = []
        var secondLinks: [String] = []

        firstSession.reconcile(
            webViews: [firstWebView],
            registration: firstRegistration,
            deliver: { link in
                if let link { firstLinks.append(link) }
            }
        )
        secondSession.reconcile(
            webViews: [secondWebView],
            registration: secondRegistration,
            deliver: { link in
                if let link { secondLinks.append(link) }
            }
        )

        firstWebView.hoveredLink.update("https://first-window.example/link")
        secondWebView.hoveredLink.update("https://second-window.example/link")
        await drainMainQueue()
        XCTAssertEqual(firstLinks, ["https://first-window.example/link"])
        XCTAssertEqual(secondLinks, ["https://second-window.example/link"])

        firstSession.invalidate()
        firstWebView.hoveredLink.update("https://first-window.example/after-teardown")
        secondWebView.hoveredLink.update("https://second-window.example/still-live")
        await drainMainQueue()

        XCTAssertEqual(firstLinks, ["https://first-window.example/link"])
        XCTAssertEqual(
            secondLinks,
            [
                "https://second-window.example/link",
                "https://second-window.example/still-live",
            ]
        )
        secondSession.invalidate()
        withExtendedLifetime((firstContainer, secondContainer)) {}
    }

    func testSplitHoverInactiveSourceNilDoesNotEraseActiveSource() async {
        let webViewRuntime = makeTestWebViewRuntimeGraph()
        let container = NSView()
        let registration = webViewRuntime.compositorRuntime.registerContainer(
            container,
            for: UUID()
        )
        let mutationGate = WindowWebContentCompositorMutationGate(
            isCurrentRegistration: webViewRuntime.compositorRuntime.owns
        )
        mutationGate.activate(registration)
        let session = WindowWebContentHoverSession(mutationGate: mutationGate)
        let firstWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        let secondWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        var latestLink: String?
        var deliveryCount = 0

        session.reconcile(
            webViews: [firstWebView, secondWebView],
            registration: registration,
            deliver: {
                latestLink = $0
                deliveryCount += 1
            }
        )
        latestLink = nil
        deliveryCount = 0

        firstWebView.hoveredLink.update("https://first-pane.example/link")
        await drainMainQueue()
        XCTAssertEqual(latestLink, "https://first-pane.example/link")
        XCTAssertEqual(deliveryCount, 1)

        secondWebView.hoveredLink.update("https://second-pane.example/link")
        await drainMainQueue()
        XCTAssertEqual(latestLink, "https://second-pane.example/link")
        XCTAssertEqual(deliveryCount, 2)

        firstWebView.hoveredLink.update(nil)
        await drainMainQueue()
        XCTAssertEqual(latestLink, "https://second-pane.example/link")
        XCTAssertEqual(deliveryCount, 2)

        secondWebView.hoveredLink.update(nil)
        await drainMainQueue()
        XCTAssertNil(latestLink)
        XCTAssertEqual(deliveryCount, 3)

        session.invalidate()
        withExtendedLifetime(container) {}
    }

    func testCloneWebViewPrimaryWindowSelectionUsesStableRegistryFallback() {
        let stableFallback = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let laterFallback = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        XCTAssertEqual(
            WebViewCreationPlanner.primaryWindowIdForClone(
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
        let unrelatedCleanupWindowID = UUID()
        let firstTargetURL = URL(string: "https://example.com/first")!
        let latestTargetURL = URL(string: "safari-web-extension://example/latest.html")!

        XCTAssertEnqueueOutcome(
            buffer.enqueue(.rebuildLiveWebViews(
                tabID: tabID,
                preferredPrimaryWindowID: firstPreferredWindowID,
                intent: .init(
                    revision: 1,
                    targetURL: firstTargetURL,
                    configuration: .normal,
                    kind: .semanticNavigation
                )
            )),
            is: .enqueued
        )
        XCTAssertEnqueueOutcome(
            buffer.enqueue(.cleanupWindow(windowID: unrelatedCleanupWindowID)),
            is: .enqueued
        )
        XCTAssertEnqueueOutcome(
            buffer.enqueue(.rebuildLiveWebViews(
                tabID: tabID,
                preferredPrimaryWindowID: latestPreferredWindowID,
                intent: .init(
                    revision: 2,
                    targetURL: latestTargetURL,
                    configuration: .currentExtensionPage,
                    kind: .semanticNavigation
                )
            )),
            is: .collapsed
        )
        XCTAssertEqual(buffer.count, 2)

        let drained = buffer.drain()
        XCTAssertEqual(drained.count, 2)
        guard case let .rebuildLiveWebViews(
            drainedTabID,
            drainedPreferredWindowID,
            drainedIntent
        ) = drained[0],
              case .cleanupWindow(let drainedCleanupWindowID) = drained[1]
        else {
            return XCTFail("Expected duplicate command replacement to keep original FIFO slot")
        }
        XCTAssertEqual(drainedTabID, tabID)
        XCTAssertEqual(drainedPreferredWindowID, latestPreferredWindowID)
        XCTAssertEqual(drainedIntent.targetURL, latestTargetURL)
        XCTAssertEqual(drainedIntent.configuration, .currentExtensionPage)
        XCTAssertEqual(drainedIntent.revision, 2)
        XCTAssertEqual(drainedCleanupWindowID, unrelatedCleanupWindowID)
    }

    func testDeferredProtectedCommandBufferPreservesGuaranteedCleanupAtCapacity() {
        var buffer = DeferredProtectedCommandBuffer()
        let commandIDs = (0..<DeferredProtectedCommandBuffer.softCapacity).map { _ in UUID() }

        for commandID in commandIDs {
            XCTAssertEnqueueOutcome(
                buffer.enqueue(.rebuildLiveWebViews(
                    tabID: commandID,
                    preferredPrimaryWindowID: nil,
                    intent: .init(
                        revision: 0,
                        targetURL: URL(string: "https://maintenance.example/\(commandID)")!,
                        configuration: .normal,
                        kind: .maintenance
                    )
                )),
                is: .enqueued
            )
        }
        XCTAssertEqual(buffer.count, DeferredProtectedCommandBuffer.softCapacity)

        let cleanupTabID = UUID()
        let cleanupWebViewID = ObjectIdentifier(WKWebView())
        XCTAssertEnqueueOutcome(
            buffer.enqueue(.cleanupTabWebView(
                webViewID: cleanupWebViewID,
                tabID: cleanupTabID
            )),
            is: .enqueued
        )
        XCTAssertEqual(buffer.count, DeferredProtectedCommandBuffer.softCapacity)

        let drained = buffer.drain()
        XCTAssertEqual(drained.count, DeferredProtectedCommandBuffer.softCapacity)
        guard case let .cleanupTabWebView(drainedWebViewID, drainedTabID) = drained.last else {
            return XCTFail("Expected guaranteed cleanup to replace low-priority work")
        }
        XCTAssertEqual(drainedWebViewID, cleanupWebViewID)
        XCTAssertEqual(drainedTabID, cleanupTabID)
        let rebuildCount = drained.reduce(into: 0) { count, command in
            if case .rebuildLiveWebViews = command {
                count += 1
            }
        }
        XCTAssertEqual(rebuildCount, commandIDs.count - 1)
    }

    func testDeferredProtectedCommandBufferPreservesUserNavigationRebuildAtCapacity() {
        var buffer = DeferredProtectedCommandBuffer()
        let maintenanceTabIDs = (0..<DeferredProtectedCommandBuffer.softCapacity).map { _ in UUID() }
        for tabID in maintenanceTabIDs {
            XCTAssertEnqueueOutcome(buffer.enqueue(.rebuildLiveWebViews(
                tabID: tabID,
                preferredPrimaryWindowID: nil,
                intent: .init(
                    revision: 0,
                    targetURL: URL(string: "https://maintenance.example/\(tabID)")!,
                    configuration: .normal,
                    kind: .maintenance
                )
            )), is: .enqueued)
        }

        let navigationTabID = UUID()
        let targetURL = URL(string: "https://example.com/user-navigation")!
        XCTAssertEnqueueOutcome(buffer.enqueue(.rebuildLiveWebViews(
            tabID: navigationTabID,
            preferredPrimaryWindowID: nil,
            intent: .init(
                revision: 1,
                targetURL: targetURL,
                configuration: .normal,
                kind: .semanticNavigation
            )
        )), is: .enqueued)

        let commands = buffer.drain()
        XCTAssertEqual(commands.count, DeferredProtectedCommandBuffer.softCapacity)
        XCTAssertTrue(commands.contains { command in
            guard case let .rebuildLiveWebViews(tabID, _, intent) = command else {
                return false
            }
            return tabID == navigationTabID
                && intent.targetURL == targetURL
                && intent.revision == 1
        })
    }

    func testDeferredProtectedCommandSoftCapacityCoalescesAndAllowsGuaranteedOverflow() {
        var buffer = DeferredProtectedCommandBuffer()
        let windowIDs = (0..<DeferredProtectedCommandBuffer.softCapacity).map { _ in UUID() }
        for windowID in windowIDs {
            XCTAssertEnqueueOutcome(
                buffer.enqueue(.cleanupWindow(windowID: windowID)),
                is: .enqueued
            )
        }

        XCTAssertEnqueueOutcome(
            buffer.enqueue(.cleanupWindow(windowID: windowIDs[0])),
            is: .collapsed
        )
        XCTAssertEqual(buffer.count, DeferredProtectedCommandBuffer.softCapacity)

        let overflowWindowID = UUID()
        XCTAssertEnqueueOutcome(
            buffer.enqueue(.cleanupWindow(windowID: overflowWindowID)),
            is: .enqueued
        )
        XCTAssertEqual(buffer.count, DeferredProtectedCommandBuffer.softCapacity + 1)
        XCTAssertTrue(buffer.drain().contains { command in
            guard case .cleanupWindow(let windowID) = command else { return false }
            return windowID == overflowWindowID
        })
    }

    func testDeferredProtectedCommandBufferPruneReturnsDroppedCommandsAndKeepsSurvivorsInOrder() {
        var buffer = DeferredProtectedCommandBuffer()
        let firstWebView = WKWebView()
        let firstWebViewID = ObjectIdentifier(firstWebView)
        let firstTabID = UUID()
        let droppedWindowID = UUID()
        let lastTabID = UUID()

        XCTAssertEnqueueOutcome(buffer.enqueue(.cleanupTabWebView(
            webViewID: firstWebViewID,
            tabID: firstTabID
        )), is: .enqueued)
        XCTAssertEnqueueOutcome(buffer.enqueue(.cleanupWindow(windowID: droppedWindowID)), is: .enqueued)
        XCTAssertEnqueueOutcome(buffer.enqueue(.rebuildLiveWebViews(
            tabID: lastTabID,
            preferredPrimaryWindowID: nil,
            intent: .init(
                revision: 0,
                targetURL: URL(string: "https://maintenance.example/last")!,
                configuration: .normal,
                kind: .maintenance
            )
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
        guard case let .cleanupTabWebView(drainedFirstWebViewID, drainedFirstTabID) = survivors[0],
              case let .rebuildLiveWebViews(
                  drainedLastTabID,
                  drainedPreferredWindowID,
                  _
              ) = survivors[1]
        else {
            return XCTFail("Expected prune to keep survivors in FIFO order")
        }
        XCTAssertEqual(drainedFirstWebViewID, firstWebViewID)
        XCTAssertEqual(drainedFirstTabID, firstTabID)
        XCTAssertEqual(drainedLastTabID, lastTabID)
        XCTAssertNil(drainedPreferredWindowID)
    }

    func testDeferredProtectedCommandBufferDoesNotReplaceSemanticRebuildWithMaintenance() {
        var buffer = DeferredProtectedCommandBuffer()
        let tabID = UUID()
        let semanticURL = URL(string: "https://example.com/user-destination")!

        XCTAssertEnqueueOutcome(buffer.enqueue(.rebuildLiveWebViews(
            tabID: tabID,
            preferredPrimaryWindowID: UUID(),
            intent: .init(
                revision: 7,
                targetURL: semanticURL,
                configuration: .currentExtensionPage,
                kind: .semanticNavigation
            )
        )), is: .enqueued)
        XCTAssertEnqueueOutcome(buffer.enqueue(.rebuildLiveWebViews(
            tabID: tabID,
            preferredPrimaryWindowID: nil,
            intent: .init(
                revision: 7,
                targetURL: URL(string: "https://example.com/stale-maintenance")!,
                configuration: .normal,
                kind: .maintenance
            )
        )), is: .collapsed)

        guard let command = buffer.drain().first,
              case .rebuildLiveWebViews(_, _, let intent) = command else {
            return XCTFail("Expected the semantic rebuild to survive coalescing")
        }
        XCTAssertEqual(intent.targetURL, semanticURL)
        XCTAssertEqual(intent.configuration, .currentExtensionPage)
        XCTAssertEqual(intent.kind, .semanticNavigation)
    }

    func testDestructiveCleanupFlowOwnerDoesNotSuppressUnclaimedNavigation() {
        let firstWebView = WKWebView()
        let secondWebView = WKWebView()
        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [] },
            liveWebViews: { _ in [] },
            waitForMutationPermission: { _ in true },
            restoreTab: { _, _ in
                .init(outcome: .failed, semanticRevision: nil)
            }
        )
        let navigation = NSObject()

        XCTAssertFalse(owner.isSuppressingNavigation(
            on: firstWebView,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation
        ))
        XCTAssertFalse(owner.isSuppressingNavigation(
            on: secondWebView,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation
        ))
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
            splitView.delegate?.splitViewDidResizeSubviews?(
                Notification(
                    name: NSSplitView.didResizeSubviewsNotification,
                    object: splitView
                )
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
        var tabsByID: [UUID: Tab] = [:]

        func currentTab(for _: BrowserWindowState) -> Tab? {
            nil
        }

        func tab(for tabID: UUID) -> Tab? {
            tabsByID[tabID]
        }

        func schedulePrepareVisibleWebViews(for _: BrowserWindowState) { /* no-op */ }

        func enqueueWindowMutationDuringHistorySwipe(
            _: HistorySwipeDeferredWindowMutationKind,
            for _: BrowserWindowState
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

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
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
