import AppKit
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class GlanceManagerTests: XCTestCase {
    func testSameURLPresentationIsNoOp() throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (_, sourceWindow) = makeRegisteredWindow(
            in: browserManager,
            selecting: sourceTab
        )
        let url = URL(string: "https://destination.example/page")!
        let origin = CGRect(x: 10, y: 20, width: 30, height: 40)

        browserManager.glanceManager.presentExternalURL(
            url,
            from: sourceTab,
            in: sourceWindow,
            originRectInWindow: origin
        )
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)

        browserManager.glanceManager.presentExternalURL(
            url,
            from: sourceTab,
            in: sourceWindow,
            originRectInWindow: origin
        )

        XCTAssertIdentical(browserManager.glanceManager.currentSession, session)
        XCTAssertEqual(browserManager.glanceManager.phase, .opening)
    }

    func testDifferentURLPresentationReplacesAndCleansOldPreview() async throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let firstURL = URL(string: "https://first.example/page")!
        let secondURL = URL(string: "https://second.example/page")!

        browserManager.glanceManager.presentExternalURL(firstURL, from: sourceTab)
        let firstSession = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let firstPreviewTab = firstSession.previewTab
        _ = try await waitForPreviewWebView(in: firstSession)
        XCTAssertNotNil(firstPreviewTab.resolvedCurrentWebView())

        browserManager.glanceManager.presentExternalURL(secondURL, from: sourceTab)

        let secondSession = try XCTUnwrap(browserManager.glanceManager.currentSession)
        XCTAssertNotEqual(secondSession.id, firstSession.id)
        XCTAssertEqual(secondSession.currentURL, secondURL)
        XCTAssertNil(firstPreviewTab.resolvedCurrentWebView())
    }

    func testExactWindowPresentationMovesSameURLBetweenPhysicalTabPresentations() throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, firstWindow) = makeRegisteredWindow(
            in: browserManager,
            selecting: sourceTab
        )
        let secondWindow = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: secondWindow
        )
        secondWindow.currentSpaceId = sourceTab.spaceId
        secondWindow.currentTabId = sourceTab.id
        windowRegistry.register(secondWindow)
        let url = try XCTUnwrap(
            URL(string: "https://destination.example/same-url")
        )

        browserManager.glanceManager.presentExternalURL(
            url,
            from: sourceTab,
            in: firstWindow
        )
        let firstSession = try XCTUnwrap(
            browserManager.glanceManager.currentSession
        )
        XCTAssertEqual(firstSession.windowId, firstWindow.id)

        browserManager.glanceManager.presentExternalURL(
            url,
            from: sourceTab,
            in: secondWindow
        )

        let secondSession = try XCTUnwrap(
            browserManager.glanceManager.currentSession
        )
        XCTAssertNotEqual(secondSession.id, firstSession.id)
        XCTAssertEqual(secondSession.currentURL, url)
        XCTAssertEqual(secondSession.windowId, secondWindow.id)
    }

    func testExactWindowPresentationReanchorsSameURLToNewSourceTab() throws {
        let browserManager = makeBrowserManager()
        let firstSourceTab = makeSourceTab(in: browserManager)
        let secondSourceTab = browserManager.regularTabLifecycleOwner
            .createNewTab(
                url: "https://second-source.example/page",
                in: browserManager.spaceStateOwner.currentSpace,
                activate: false
            )
        let (_, windowState) = makeRegisteredWindow(
            in: browserManager,
            selecting: firstSourceTab
        )
        let url = try XCTUnwrap(
            URL(string: "https://destination.example/same-url")
        )
        let origin = CGRect(x: 1, y: 2, width: 30, height: 40)

        browserManager.glanceManager.presentExternalURL(
            url,
            from: firstSourceTab,
            in: windowState,
            originRectInWindow: origin
        )
        let firstSession = try XCTUnwrap(
            browserManager.glanceManager.currentSession
        )
        windowState.currentTabId = secondSourceTab.id

        browserManager.glanceManager.presentExternalURL(
            url,
            from: secondSourceTab,
            in: windowState,
            originRectInWindow: origin
        )

        let secondSession = try XCTUnwrap(
            browserManager.glanceManager.currentSession
        )
        XCTAssertNotEqual(secondSession.id, firstSession.id)
        XCTAssertIdentical(secondSession.sourceTab, secondSourceTab)
        XCTAssertIdentical(
            browserManager.glanceManager.presentedSession(for: windowState),
            secondSession
        )
    }

    func testExactWindowPresentationReanchorsSameURLWhenOriginChanges() throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (_, windowState) = makeRegisteredWindow(
            in: browserManager,
            selecting: sourceTab
        )
        let url = try XCTUnwrap(
            URL(string: "https://destination.example/same-url")
        )
        let firstOrigin = CGRect(x: 1, y: 2, width: 30, height: 40)
        let secondOrigin = CGRect(x: 50, y: 60, width: 70, height: 80)

        browserManager.glanceManager.presentExternalURL(
            url,
            from: sourceTab,
            in: windowState,
            originRectInWindow: firstOrigin
        )
        let firstSession = try XCTUnwrap(
            browserManager.glanceManager.currentSession
        )

        browserManager.glanceManager.presentExternalURL(
            url,
            from: sourceTab,
            in: windowState,
            originRectInWindow: secondOrigin
        )

        let secondSession = try XCTUnwrap(
            browserManager.glanceManager.currentSession
        )
        XCTAssertNotEqual(secondSession.id, firstSession.id)
        XCTAssertEqual(secondSession.originRectInWindow, secondOrigin)
    }

    func testPresentationWithoutSourceUsesActiveWindowSpaceInsteadOfGlobalCurrentSpace() throws {
        let browserManager = makeBrowserManager()
        let windowSpace = installTestSpace(in: browserManager.spaceStateOwner, name: "Window Space")
        let globalSpace = installTestSpace(in: browserManager.spaceStateOwner, name: "Global Space")
        browserManager.spaceStateOwner.replaceCurrentSpace(globalSpace)
        let windowRegistry = browserManager.windowRegistry
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        windowState.currentSpaceId = windowSpace.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        let url = try XCTUnwrap(URL(string: "https://destination.example/page"))

        browserManager.glanceManager.presentExternalURL(url, from: nil)

        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        XCTAssertEqual(session.previewTab.spaceId, windowSpace.id)
    }

    func testDismissCleansPreviewAndReturnsIdle() async throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        _ = try await waitForPreviewWebView(in: session)
        XCTAssertNotNil(previewTab.resolvedCurrentWebView())

        browserManager.glanceManager.finishAnimatedDismissal(sessionID: session.id)

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertFalse(browserManager.glanceManager.isActive)
        XCTAssertNil(previewTab.resolvedCurrentWebView())
    }

    func testDismissGlanceImmediatelyClearsPreviewInstance() async throws {
        let browserManager = makeBrowserManager()
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
        XCTAssertNil(previewTab.resolvedCurrentWebView())
        XCTAssertNil(previewTab.resolvedPrimaryWindowId())
    }

    func testWebKitCloseDismissesAndCleansPreviewInstance() async throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        let webView = try await waitForPreviewWebView(in: session)

        XCTAssertTrue(browserManager.webViewCloseRouter.handleWebViewDidClose(webView))

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertNil(previewTab.resolvedCurrentWebView())
        XCTAssertNil(previewTab.resolvedPrimaryWindowId())
    }

    func testWebKitCloseForTrackedRegularWebViewClosesOwningTab() {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, sourceWindow) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let webView = FocusableWKWebView()
        webView.owningTab = sourceTab

        let admission = browserManager.testWebViewRuntime()
            .trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
                webView,
                for: sourceTab,
                in: sourceWindow.id
            )
        XCTAssertTrue(admission.isAccepted)

        XCTAssertTrue(browserManager.webViewCloseRouter.handleWebViewDidClose(webView))

        XCTAssertNil(browserManager.tabCollectionMembershipOwner.tab(for: sourceTab.id))
        XCTAssertNil(browserManager.testWebViewRuntime().ownershipQuery.webView(
            for: sourceTab.id,
            in: sourceWindow.id
        ))
        withExtendedLifetime(windowRegistry) { /* BrowserManager keeps the registry weak. */ }
    }

    func testWebKitCloseForTrackedWebViewWithStaleOwnerCleansSlotWithoutClosingAnotherWindow() {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, visibleWindow) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let staleOwnerWindowID = UUID()
        let webView = FocusableWKWebView()
        webView.owningTab = sourceTab

        let admission = browserManager.testWebViewRuntime()
            .trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
                webView,
                for: sourceTab,
                in: staleOwnerWindowID
            )
        XCTAssertTrue(admission.isAccepted)

        XCTAssertTrue(browserManager.webViewCloseRouter.handleWebViewDidClose(webView))

        XCTAssertNotNil(browserManager.tabCollectionMembershipOwner.tab(for: sourceTab.id))
        XCTAssertEqual(visibleWindow.currentTabId, sourceTab.id)
        XCTAssertNil(browserManager.testWebViewRuntime().ownershipQuery.webView(
            for: sourceTab.id,
            in: staleOwnerWindowID
        ))
        withExtendedLifetime(windowRegistry) { /* BrowserManager keeps the registry weak. */ }
    }

    func testWebKitCloseRejectsTrackedTabOutsideOwningWindowResidence() {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, sourceWindow) = makeRegisteredWindow(
            in: browserManager,
            selecting: sourceTab
        )
        let otherSpace = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Other Space"
        )
        let mismatchedWindow = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: mismatchedWindow
        )
        mismatchedWindow.currentSpaceId = otherSpace.id
        windowRegistry.register(mismatchedWindow)
        let webView = FocusableWKWebView()
        webView.owningTab = sourceTab

        let admission = browserManager.testWebViewRuntime()
            .trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
                webView,
                for: sourceTab,
                in: mismatchedWindow.id
            )
        XCTAssertTrue(admission.isAccepted)

        XCTAssertTrue(
            browserManager.webViewCloseRouter.handleWebViewDidClose(webView)
        )

        XCTAssertIdentical(
            browserManager.tabCollectionMembershipOwner.tab(
                for: sourceTab.id
            ),
            sourceTab
        )
        XCTAssertEqual(sourceWindow.currentTabId, sourceTab.id)
        XCTAssertNil(
            browserManager.testWebViewRuntime().ownershipQuery.webView(
                for: sourceTab.id,
                in: mismatchedWindow.id
            )
        )
        withExtendedLifetime(windowRegistry) {}
    }

    func testMoveToNewTabAdoptsSamePreviewTabAndWebView() async throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        let webView = try await waitForPreviewWebView(in: session)

        browserManager.glanceManager.moveToNewTab()

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertIdentical(browserManager.tabCollectionMembershipOwner.tab(for: previewTab.id), previewTab)
        XCTAssertIdentical(previewTab.resolvedCurrentWebView(), webView)
    }

    func testRejectedPreviewAdoptionKeepsSessionOpenAndUnselected() throws {
        let manager = GlanceManager()
        var selectedTabIDs: [UUID] = []
        manager.attach(runtime: makeRuntime(
            adoptPreviewTab: { _, _, _ in nil },
            selectPromotedTabInActiveWindow: { selectedTabIDs.append($0.id) }
        ))
        XCTAssertTrue(
            manager.presentExternalURL(
                URL(string: "https://rejected-promotion.example")!,
                from: nil
            )
        )
        let session = try XCTUnwrap(manager.currentSession)

        manager.moveToNewTab()

        XCTAssertIdentical(manager.currentSession, session)
        XCTAssertEqual(manager.phase, .open)
        XCTAssertTrue(selectedTabIDs.isEmpty)
    }

    func testMoveToNewTabPromotesPreviewInSourceWindow() async throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, sourceWindow) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let otherWindow = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: otherWindow
        )
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
        XCTAssertIdentical(browserManager.tabCollectionMembershipOwner.tab(for: previewTab.id), previewTab)
        XCTAssertIdentical(previewTab.resolvedCurrentWebView(), webView)
        XCTAssertEqual(sourceWindow.currentTabId, previewTab.id)
        XCTAssertNotEqual(otherWindow.currentTabId, previewTab.id)
    }

    func testMoveToNewTabCanWaitForDisplayAttachmentBeforeFinishingPromotion() async throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, sourceWindow) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        _ = try await waitForPreviewWebView(in: session)

        browserManager.glanceManager.moveToNewTab(finishesAfterDisplayUpdate: true)

        XCTAssertIdentical(browserManager.glanceManager.currentSession, session)
        XCTAssertEqual(browserManager.glanceManager.phase, .promoting)
        XCTAssertIdentical(browserManager.tabCollectionMembershipOwner.tab(for: previewTab.id), previewTab)
        XCTAssertNotNil(previewTab.resolvedCurrentWebView())
        XCTAssertEqual(sourceWindow.currentTabId, previewTab.id)

        browserManager.glanceManager.finishPromotedSession(sessionID: session.id)

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        withExtendedLifetime(windowRegistry) { /* no-op */ }
    }

    func testRemovingPromotionWindowReportsCancelledThroughGlanceRuntimeExactlyOnce() async throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, windowState) = makeRegisteredWindow(
            in: browserManager,
            selecting: sourceTab
        )
        let url = try XCTUnwrap(URL(string: "https://destination.example/page"))

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let webView = try await waitForPreviewWebView(in: session)
        let host = SumiWebViewContainerView(
            tabID: session.previewTab.id,
            webView: webView
        )
        let compositorContainer = NSView()
        var outcomes: [PromotedHostAttachmentOutcome] = []
        browserManager.webViewRuntime.compositorRuntime.registerContainer(
            compositorContainer,
            for: windowState.id
        )

        XCTAssertTrue(browserManager.glanceManager.registerPromotedHost(
            host,
            for: session,
            attachmentCompletion: { outcomes.append($0) }
        ))

        browserManager.webViewRuntime.compositorRuntime.removeContainer(
            for: windowState.id
        )
        browserManager.webViewRuntime.compositorRuntime.removeContainer(
            for: windowState.id
        )

        XCTAssertEqual(outcomes, [.cancelled])
        var rejectedOutcomes: [PromotedHostAttachmentOutcome] = []
        XCTAssertFalse(browserManager.glanceManager.registerPromotedHost(
            host,
            for: session,
            attachmentCompletion: { rejectedOutcomes.append($0) }
        ))
        XCTAssertTrue(rejectedOutcomes.isEmpty)
        withExtendedLifetime(compositorContainer) {}
        withExtendedLifetime(windowRegistry) { /* BrowserManager keeps the registry weak. */ }
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
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let sourceSpace = try XCTUnwrap(sourceTab.spaceId.flatMap { spaceId in
            browserManager.spaceStateOwner.spaces.first { $0.id == spaceId }
        })
        let olderTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://older.example/page",
            in: sourceSpace,
            activate: false
        )
        let (windowRegistry, sourceWindow) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        browserManager.selectTab(olderTab, in: sourceWindow)
        browserManager.selectTab(sourceTab, in: sourceWindow)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        let webView = try await waitForPreviewWebView(in: session)

        browserManager.glanceManager.moveToSplitView()

        let splitGroup = try XCTUnwrap(
            browserManager.splitGroupStore.group(
                containing: .regularTab(previewTab.id)
            )
        )
        guard case .regularTab(let placeholderId) = splitGroup.memberIDs.last else {
            return XCTFail("Expected the split picker placeholder to remain a regular tab.")
        }
        let placeholderTab = try XCTUnwrap(browserManager.tabCollectionMembershipOwner.tab(for: placeholderId))
        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertEqual(
            splitGroup.memberIDs,
            [.regularTab(previewTab.id), .regularTab(placeholderId)]
        )
        XCTAssertEqual(
            sourceWindow.splitSelection,
            WindowSplitSelection(
                groupID: splitGroup.id,
                activeMemberID: .regularTab(placeholderId)
            )
        )
        XCTAssertFalse(splitGroup.contains(.regularTab(sourceTab.id)))
        XCTAssertTrue(placeholderTab.representsSumiEmptySurface)
        XCTAssertEqual(windowRegistry.activeWindow?.id, sourceWindow.id)
        XCTAssertEqual(sourceWindow.currentTabId, placeholderId)
        XCTAssertTrue(sourceWindow.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(sourceWindow.commandPalettePresentationReason, .splitTabPicker)
        XCTAssertTrue(sourceWindow.commandPaletteDraftNavigatesCurrentTab)
        XCTAssertIdentical(previewTab.resolvedCurrentWebView(), webView)

        let activeTabs = ActiveTabSuggestionOwner(
            allTabsForCurrentProfile: {
                browserManager.tabCollectionMembershipOwner
                    .allTabsForCurrentProfile()
            },
            liveShortcutTabs: { windowID in
                browserManager.shortcutPresentationOwner
                    .liveShortcutTabs(in: windowID)
            },
            shortcutLiveTab: { pinID, windowID in
                browserManager.shortcutPresentationOwner.shortcutLiveTab(
                    for: pinID,
                    in: windowID
                )
            },
            visibleSplitTabIds: { windowID in
                Set(
                    browserManager.runtimePortConnection.current?
                        .visibleSplitTabIds(for: windowID) ?? []
                )
            }
        )
        let suggestedTabs = activeTabs.tabs(for: sourceWindow)
        XCTAssertEqual(suggestedTabs.prefix(2).map(\.id), [sourceTab.id, olderTab.id])
        XCTAssertFalse(suggestedTabs.contains { $0.id == previewTab.id })
        XCTAssertFalse(suggestedTabs.contains { $0.id == placeholderId })

        browserManager.urlBarBundle.commandPaletteCommit.commitActivation(
            .tab(sourceTab.id),
            in: sourceWindow
        )

        let filledGroup = try XCTUnwrap(
            browserManager.splitGroupStore.group(
                containing: .regularTab(previewTab.id)
            )
        )
        XCTAssertEqual(
            filledGroup.memberIDs,
            [.regularTab(previewTab.id), .regularTab(sourceTab.id)]
        )
        XCTAssertEqual(
            sourceWindow.splitSelection,
            WindowSplitSelection(
                groupID: filledGroup.id,
                activeMemberID: .regularTab(sourceTab.id)
            )
        )
        XCTAssertEqual(sourceWindow.currentTabId, sourceTab.id)
        XCTAssertNil(browserManager.tabCollectionMembershipOwner.tab(for: placeholderId))
        XCTAssertFalse(sourceWindow.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(sourceWindow.commandPalettePresentationReason, .none)
    }

    func testGlancePresentationStaysPinnedToSourceTabSelection() {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let otherTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://other.example/page",
            in: browserManager.spaceStateOwner.currentSpace,
            activate: false
        )
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        windowState.currentSpaceId = sourceTab.spaceId
        windowState.currentTabId = sourceTab.id

        let previewTab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://destination.example/page")!,
            name: "Destination"
        )
        previewTab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let session = GlanceSession(
            targetURL: previewTab.url,
            windowId: windowState.id,
            sourceTab: sourceTab,
            previewTab: previewTab,
            originRectInWindow: CGRect(x: 10, y: 10, width: 44, height: 44)
        )
        browserManager.glanceManager.currentSession = session
        browserManager.glanceManager.transition(to: .open)

        XCTAssertIdentical(browserManager.glanceManager.presentedSession(for: windowState), session)
        XCTAssertIdentical(browserManager.glanceManager.activePreviewTab(for: windowState), previewTab)

        windowState.currentTabId = otherTab.id

        XCTAssertNil(browserManager.glanceManager.presentedSession(for: windowState))
        XCTAssertNil(browserManager.glanceManager.activePreviewTab(for: windowState))
        XCTAssertIdentical(browserManager.glanceManager.currentSession, session)
        XCTAssertIdentical(browserManager.glanceManager.sidebarSession(for: windowState), session)

        windowState.currentTabId = sourceTab.id

        XCTAssertIdentical(browserManager.glanceManager.presentedSession(for: windowState), session)
    }

    func testGlancePreviewPermissionSurfaceCountsAsActiveAndVisible() async throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, _) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        let webView = try await waitForPreviewWebView(
            in: session,
            manager: browserManager.glanceManager
        )

        XCTAssertNotEqual(
            windowRegistry.activeWindow?.currentTabId,
            previewTab.id
        )
        XCTAssertNil(previewTab.resolvedPrimaryWindowId())
        XCTAssertTrue(previewTab.permissionRequestIsActiveSurface(for: webView))
        XCTAssertTrue(previewTab.permissionRequestIsVisibleSurface(for: webView))
        XCTAssertFalse(previewTab.permissionRequestIsActiveSurface(for: WKWebView()))
        XCTAssertFalse(previewTab.permissionRequestIsVisibleSurface(for: WKWebView()))
        withExtendedLifetime(windowRegistry) { /* no-op */ }
    }

    func testGlanceSessionObserveAppliesInitialWebViewStateSynchronously() {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let targetURL = URL(string: "https://destination.example/page")!
        let previewTab = browserManager.tabFactory.makeTab(
            url: targetURL,
            name: "Destination"
        )
        previewTab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let session = GlanceSession(
            targetURL: targetURL,
            windowId: UUID(),
            sourceTab: sourceTab,
            previewTab: previewTab,
            originRectInWindow: .zero
        )
        let webView = WKWebView()

        XCTAssertTrue(session.isLoading)

        session.observe(webView)

        XCTAssertFalse(session.isLoading)
        XCTAssertEqual(session.estimatedProgress, webView.estimatedProgress)
    }

    func testGlanceSessionSnapshotRestoresPreviewForWindow() throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let (_, windowState) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
        let targetURL = URL(string: "https://destination.example/page")!
        let snapshot = GlanceSessionSnapshot(
            targetURL: targetURL,
            currentURL: targetURL,
            title: "Destination",
            sourceTabId: sourceTab.id,
            originRectInWindow: GlanceSessionRectSnapshot(
                CGRect(x: 12, y: 18, width: 44, height: 44)
            )
        )

        browserManager.glanceManager.restoreSession(snapshot, in: windowState)

        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        XCTAssertEqual(session.windowId, windowState.id)
        XCTAssertEqual(session.currentURL, targetURL)
        XCTAssertEqual(session.title, "Destination")
        XCTAssertIdentical(session.sourceTab, sourceTab)
        XCTAssertIdentical(browserManager.glanceManager.presentedSession(for: windowState), session)
    }

    func testGlanceSessionRestoreRebindsToSourceTabSelection() throws {
        let browserManager = makeBrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let otherTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://other.example/page",
            in: browserManager.spaceStateOwner.currentSpace,
            activate: false
        )
        let (_, windowState) = makeRegisteredWindow(in: browserManager, selecting: otherTab)
        let targetURL = URL(string: "https://destination.example/page")!
        let snapshot = GlanceSessionSnapshot(
            targetURL: targetURL,
            currentURL: targetURL,
            title: "Destination",
            sourceTabId: sourceTab.id,
            originRectInWindow: nil
        )

        browserManager.glanceManager.restoreSession(snapshot, in: windowState)

        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        XCTAssertEqual(windowState.currentTabId, sourceTab.id)
        XCTAssertIdentical(session.sourceTab, sourceTab)
        XCTAssertIdentical(browserManager.glanceManager.presentedSession(for: windowState), session)
    }

    func testGlanceRestoreRelocatesCurrentShortcutSourceToCurrentPage() throws {
        let browserManager = makeBrowserManager()
        let profileID = UUID()
        let sourceSpace = installTestSpace(in: browserManager.spaceStateOwner, name: "Source", profileID: profileID)
        let targetSpace = installTestSpace(in: browserManager.spaceStateOwner, name: "Target", profileID: profileID)
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://source.example")!,
            title: "Source"
        )
        browserManager.shortcutPinCollectionStateOwner
            .replacePinnedByProfile([profileID: [pin]])
        let sourceTab = Tab(loadsCachedFaviconOnInit: false)
        sourceTab.bindToShortcutPin(pin)
        sourceTab.profileId = profileID
        let (registry, windowState) = makeRegisteredWindow(
            in: browserManager,
            selecting: sourceTab
        )
        windowState.currentSpaceId = targetSpace.id
        XCTAssertTrue(browserManager.liveShortcutTabs.register(
            sourceTab,
            for: pin.id,
            in: windowState.id,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: windowState.id,
                spaceID: sourceSpace.id,
                profileID: profileID
            )
        ))
        let targetURL = URL(string: "https://destination.example")!

        browserManager.glanceManager.restoreSession(
            GlanceSessionSnapshot(
                targetURL: targetURL,
                currentURL: targetURL,
                title: "Destination",
                sourceTabId: sourceTab.id,
                sourceShortcutPinId: pin.id,
                sourceShortcutPinRole: pin.role,
                originRectInWindow: nil
            ),
            in: windowState
        )

        XCTAssertIdentical(
            browserManager.glanceManager.currentSession?.sourceTab,
            sourceTab
        )
        XCTAssertEqual(windowState.currentTabId, sourceTab.id)
        XCTAssertEqual(
            browserManager.liveShortcutTabs
                .entry(containing: sourceTab)?.presentationPage,
            LiveShortcutPresentationPageReceipt(
                windowID: windowState.id,
                spaceID: targetSpace.id,
                profileID: profileID
            )
        )
        withExtendedLifetime(registry) {}
    }

    func testGlanceSessionRestoreDoesNotPresentWhenSourceTabIsMissing() {
        let browserManager = makeBrowserManager()
        browserManager.startupRestoreLifecycle.markLoadFinished()
        let selectedTab = makeSourceTab(in: browserManager)
        let (_, windowState) = makeRegisteredWindow(in: browserManager, selecting: selectedTab)
        let targetURL = URL(string: "https://destination.example/page")!
        let snapshot = GlanceSessionSnapshot(
            targetURL: targetURL,
            currentURL: targetURL,
            title: "Destination",
            sourceTabId: UUID(),
            originRectInWindow: nil
        )

        browserManager.glanceManager.restoreSession(snapshot, in: windowState)

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertNil(browserManager.glanceManager.presentedSession(for: windowState))
        XCTAssertEqual(windowState.currentTabId, selectedTab.id)
    }

    func testGlanceSessionRestoreUsesInjectedRuntimeWithoutBrowserManager() throws {
        let manager = GlanceManager()
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState()
        let sourceTab = Tab(
            url: URL(string: "https://source.example/page")!,
            name: "Source"
        )
        let targetURL = URL(string: "https://destination.example/page")!
        var restoredSelectionIds: [UUID] = []
        var persistedWindowIds: [UUID] = []

        windowRegistry.register(windowState)
        manager.windowRegistry = windowRegistry
        manager.attach(
            runtime: makeRuntime(
                tab: { tabId in
                    tabId == sourceTab.id ? sourceTab : nil
                },
                currentTab: { _ in nil },
                restoreSourceSelection: { tab, windowState in
                    restoredSelectionIds.append(tab.id)
                    windowState.currentTabId = tab.id
                },
                persistWindowSession: { windowState in
                    persistedWindowIds.append(windowState.id)
                },
                makePreviewTab: { url, _, restoredWindowState in
                    XCTAssertIdentical(restoredWindowState, windowState)
                    return Tab(url: url, name: url.host ?? "Glance")
                }
            )
        )

        manager.restoreSession(
            GlanceSessionSnapshot(
                targetURL: targetURL,
                currentURL: targetURL,
                title: "Destination",
                sourceTabId: sourceTab.id,
                originRectInWindow: nil
            ),
            in: windowState
        )

        let session = try XCTUnwrap(manager.currentSession)
        XCTAssertEqual(session.windowId, windowState.id)
        XCTAssertIdentical(session.sourceTab, sourceTab)
        XCTAssertEqual(restoredSelectionIds, [sourceTab.id])
        XCTAssertEqual(windowState.currentTabId, sourceTab.id)
        XCTAssertTrue(persistedWindowIds.isEmpty)

        manager.dismissGlance()

        XCTAssertEqual(persistedWindowIds, [windowState.id])
    }

    @discardableResult
    private func makeBrowserManager() -> BrowserManager {
        BrowserManager(windowRegistry: WindowRegistry())
    }

    @discardableResult
    private func makeRegisteredWindow(
        in browserManager: BrowserManager,
        selecting tab: Tab
    ) -> (WindowRegistry, BrowserWindowState) {
        let windowRegistry = browserManager.windowRegistry

        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        windowState.currentSpaceId = tab.spaceId
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (windowRegistry, windowState)
    }

    private func makeSourceTab(in browserManager: BrowserManager) -> Tab {
        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "Glance Tests")
        return browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: true
        )
    }

    private func waitForPreviewWebView(
        in session: GlanceSession,
        manager: GlanceManager? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> WKWebView {
        for _ in 0..<20 {
            if let webView = manager?.runtime?.previewWebView(session.previewTab)
                ?? session.previewTab.resolvedCurrentWebView() {
                return webView
            }
            await Task.yield()
        }
        return try XCTUnwrap(
            manager?.runtime?.previewWebView(session.previewTab)
                ?? session.previewTab.resolvedCurrentWebView(),
            file: file,
            line: line
        )
    }

    private func makeRuntime(
        tab: @escaping @MainActor (UUID) -> Tab? = { _ in nil },
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab? = { _ in nil },
        restoreSourceSelection: @escaping @MainActor (Tab, BrowserWindowState) -> Void = { _, _ in /* No-op. */ },
        persistWindowSession: @escaping @MainActor (BrowserWindowState) -> Void = { _ in /* No-op. */ },
        adoptPreviewTab: @escaping @MainActor (Tab, Tab?, BrowserWindowState?) -> Tab? = { previewTab, _, _ in previewTab },
        selectPromotedTabInActiveWindow: @escaping @MainActor (Tab) -> Void = { _ in /* No-op. */ },
        makePreviewTab: @escaping @MainActor (URL, Tab?, BrowserWindowState?) -> Tab = { url, _, _ in
            Tab(url: url, name: url.host ?? "Glance")
        }
    ) -> GlanceManager.Runtime {
        GlanceManager.Runtime(
            windowStateContainingTab: { _ in nil },
            hasLoadedInitialTabData: { true },
            tab: tab,
            shortcutPin: { _ in nil },
            activateShortcutPin: { pin, _, _ in
                Tab(url: pin.launchURL, name: pin.title)
            },
            currentTab: currentTab,
            restoreSourceSelection: restoreSourceSelection,
            visibleSplitTabCount: { _ in 0 },
            dismissCommandPaletteIfVisible: { _ in false },
            isFindBarVisible: { false },
            hideFindBar: { /* No-op. */ },
            dismissFindSessionIfOwned: { _ in /* No-op. */ },
            persistWindowSession: persistWindowSession,
            withPreparedPreviewTab: { url, sourceTab, windowState, publish in
                publish(makePreviewTab(url, sourceTab, windowState))
            },
            adoptPreviewTab: adoptPreviewTab,
            selectPromotedTab: { _, _ in /* No-op. */ },
            selectPromotedTabInActiveWindow: selectPromotedTabInActiveWindow,
            createSplitPlaceholder: { _ in /* No-op. */ },
            registerPromotedHost: { _, _, _, _ in false },
            previewWebView: { tab in tab.resolvedCurrentWebView() },
            ensurePreviewWebView: { tab, _ in
                tab.ensureUntrackedNormalWebView(
                    reason: "GlanceManagerTests.ensurePreviewWebView"
                )
            },
            ownsPreviewWebView: { tab, webView in
                tab.resolvedCurrentWebView() === webView || tab.resolvedAssignedWebView() === webView
            },
            releasePreviewWebView: { tab in
                if let webView = tab.resolvedCurrentWebView() {
                    tab.cleanupCloneWebView(webView)
                }
                // Mirror canonical untracked WebView release for injected runtime tests.
                tab.clearCurrentWebViewOwnership()
            }
        )
    }
}
