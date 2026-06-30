import WebKit
import XCTest

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

        XCTAssertIdentical(browserManager.glanceManager.currentSession, session)
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

    func testWebKitCloseForTrackedRegularWebViewClosesOwningTab() {
        let browserManager = BrowserManager()
        browserManager.webViewCoordinator = WebViewCoordinator()
        let sourceTab = makeSourceTab(in: browserManager)
        let (windowRegistry, sourceWindow) = makeRegisteredWindow(in: browserManager, selecting: sourceTab)
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
        withExtendedLifetime(windowRegistry) { /* BrowserManager keeps the registry weak. */ }
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
        XCTAssertIdentical(browserManager.tabManager.tab(for: previewTab.id), previewTab)
        XCTAssertIdentical(previewTab.existingWebView, webView)
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
        XCTAssertIdentical(browserManager.tabManager.tab(for: previewTab.id), previewTab)
        XCTAssertIdentical(previewTab.existingWebView, webView)
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

        XCTAssertIdentical(browserManager.glanceManager.currentSession, session)
        XCTAssertEqual(browserManager.glanceManager.phase, .promoting)
        XCTAssertIdentical(browserManager.tabManager.tab(for: previewTab.id), previewTab)
        XCTAssertNotNil(previewTab.existingWebView)
        XCTAssertEqual(sourceWindow.currentTabId, previewTab.id)

        browserManager.glanceManager.finishPromotedSession(sessionID: session.id)

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        withExtendedLifetime(windowRegistry) { /* no-op */ }
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
        let sourceSpace = try XCTUnwrap(sourceTab.spaceId.flatMap { spaceId in
            browserManager.tabManager.spaces.first { $0.id == spaceId }
        })
        let olderTab = browserManager.tabManager.createNewTab(
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

        let splitGroup = try XCTUnwrap(browserManager.tabManager.splitGroup(containing: previewTab.id))
        let placeholderId = try XCTUnwrap(splitGroup.tabIds.last)
        let placeholderTab = try XCTUnwrap(browserManager.tabManager.tab(for: placeholderId))
        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertEqual(splitGroup.tabIds, [previewTab.id, placeholderId])
        XCTAssertEqual(splitGroup.activeTabId, placeholderId)
        XCTAssertFalse(splitGroup.contains(sourceTab.id))
        XCTAssertTrue(placeholderTab.representsSumiEmptySurface)
        XCTAssertEqual(windowRegistry.activeWindow?.id, sourceWindow.id)
        XCTAssertEqual(sourceWindow.currentTabId, placeholderId)
        XCTAssertTrue(sourceWindow.isFloatingBarVisible)
        XCTAssertEqual(sourceWindow.floatingBarPresentationReason, .splitTabPicker)
        XCTAssertTrue(sourceWindow.floatingBarDraftNavigatesCurrentTab)
        XCTAssertIdentical(previewTab.existingWebView, webView)

        let searchManager = SearchManager()
        searchManager.setTabManager(browserManager.tabManager)
        searchManager.showActiveTabSuggestions(for: sourceWindow)
        let suggestedTabs = searchManager.suggestions.compactMap { suggestion -> Tab? in
            guard case .tab(let tab) = suggestion.type else { return nil }
            return tab
        }
        XCTAssertEqual(suggestedTabs.prefix(2).map(\.id), [sourceTab.id, olderTab.id])
        XCTAssertFalse(suggestedTabs.contains { $0.id == previewTab.id })
        XCTAssertFalse(suggestedTabs.contains { $0.id == placeholderId })

        browserManager.commitFloatingBarSuggestion(
            SearchManager.SearchSuggestion(text: sourceTab.name, type: .tab(sourceTab)),
            in: sourceWindow
        )

        let filledGroup = try XCTUnwrap(browserManager.tabManager.splitGroup(containing: previewTab.id))
        XCTAssertEqual(filledGroup.tabIds, [previewTab.id, sourceTab.id])
        XCTAssertEqual(filledGroup.activeTabId, sourceTab.id)
        XCTAssertEqual(sourceWindow.currentTabId, sourceTab.id)
        XCTAssertNil(browserManager.tabManager.tab(for: placeholderId))
        XCTAssertFalse(sourceWindow.isFloatingBarVisible)
        XCTAssertEqual(sourceWindow.floatingBarPresentationReason, .none)
    }

    func testGlancePresentationStaysPinnedToSourceTabSelection() {
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
            name: "Destination"
        )
        previewTab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())
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
        withExtendedLifetime(windowRegistry) { /* no-op */ }
    }

    func testGlanceSessionObserveAppliesInitialWebViewStateSynchronously() {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let targetURL = URL(string: "https://destination.example/page")!
        let previewTab = Tab(url: targetURL, name: "Destination")
        previewTab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())
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
        let browserManager = BrowserManager()
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
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let otherTab = browserManager.tabManager.createNewTab(
            url: "https://other.example/page",
            in: browserManager.tabManager.currentSpace,
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

    func testGlanceSessionRestoreDoesNotPresentWhenSourceTabIsMissing() {
        let browserManager = BrowserManager()
        browserManager.tabManager.markInitialDataLoadFinished()
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
                makePreviewTab: { url, _ in
                    Tab(url: url, name: url.host ?? "Glance")
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

    private func makeRuntime(
        tab: @escaping @MainActor (UUID) -> Tab? = { _ in nil },
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab? = { _ in nil },
        restoreSourceSelection: @escaping @MainActor (Tab, BrowserWindowState) -> Void = { _, _ in },
        persistWindowSession: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
        makePreviewTab: @escaping @MainActor (URL, Tab?) -> Tab = { url, _ in
            Tab(url: url, name: url.host ?? "Glance")
        }
    ) -> GlanceManager.Runtime {
        GlanceManager.Runtime(
            windowStateContainingTab: { _ in nil },
            hasLoadedInitialTabData: { true },
            tab: tab,
            shortcutPin: { _ in nil },
            shortcutLiveTab: { _, _ in nil },
            activateShortcutPin: { pin, _, _ in
                Tab(url: pin.launchURL, name: pin.title)
            },
            currentTab: currentTab,
            restoreSourceSelection: restoreSourceSelection,
            visibleSplitTabCount: { _ in 0 },
            dismissFloatingBarIfVisible: { _ in false },
            isFindBarVisible: { false },
            findCurrentTabId: { nil },
            hideFindBar: {},
            updateFindManagerCurrentTab: {},
            persistWindowSession: persistWindowSession,
            makePreviewTab: makePreviewTab,
            adoptPreviewTab: { previewTab, _, _ in previewTab },
            selectPromotedTab: { _, _ in },
            selectPromotedTabInActiveWindow: { _ in },
            createSplitPlaceholder: { _ in },
            registerPromotedHost: { _, _, _, _ in false }
        )
    }
}
