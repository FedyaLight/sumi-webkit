import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class NavigationToolbarContextOwnerTests: XCTestCase {
    func testToolbarContextUsesBoundWindowForCurrentTabAndWebView() {
        let harness = NavigationToolbarContextHarness()
        let webView = WKWebView()
        harness.register(webView, for: harness.tab)

        let context = harness.owner.navigationToolbarContext(
            for: harness.windowState
        )

        XCTAssertIdentical(context.currentTab(), harness.tab)
        XCTAssertIdentical(context.webView(harness.tab), webView)
    }

    func testNavigationHistorySelectedURLOpensForegroundInWindowSpace() {
        let harness = NavigationToolbarContextHarness()
        let targetURL = URL(string: "https://selected.example/path")!

        harness.owner
            .navigationHistoryContext(for: harness.windowState)
            .openURLInNewTab(targetURL, true, harness.tab)

        let opened = harness.tabs.first { $0.id != harness.tab.id }
        XCTAssertEqual(opened?.url, targetURL)
        XCTAssertEqual(opened?.spaceId, harness.space.id)
        XCTAssertEqual(harness.windowState.currentTabId, opened?.id)
    }

    func testNavigationHistoryBackgroundURLOpensInWindowSpaceWithoutForegroundActivation() {
        let harness = NavigationToolbarContextHarness()
        let targetURL = URL(string: "https://background.example/path")!

        harness.owner
            .navigationHistoryContext(for: harness.windowState)
            .openURLInNewTab(targetURL, false, harness.tab)

        let opened = harness.tabs.first { $0.id != harness.tab.id }
        XCTAssertEqual(opened?.url, targetURL)
        XCTAssertEqual(opened?.spaceId, harness.space.id)
        XCTAssertEqual(harness.windowState.currentTabId, harness.tab.id)
    }

    func testNavigationHistoryCurrentURLUsesBoundWindowScopedAction() {
        let harness = NavigationToolbarContextHarness()
        let targetURL = URL(string: "https://current.example/path")!
        let history = NavigationToolbarHistoryRecorder()
        history.activePagesByWindowID[harness.windowState.id] = ActivePageResolution(
            source: .selectedTab,
            windowState: harness.windowState,
            tab: harness.tab,
            url: harness.tab.url,
            canonicalWebView: nil
        )
        let owner = harness.makeOwner(history: history.owner)

        owner.navigationHistoryContext(for: harness.windowState)
            .openURLInCurrentTab(targetURL, nil)

        XCTAssertEqual(history.loadedURLs, [targetURL])
        XCTAssertIdentical(history.loadedWindows.first, harness.windowState)
    }

    func testNavigationHistoryDeadBoundWindowDoesNotRetargetToAnotherWindow() {
        let browserManager = BrowserManager()
        let history = NavigationToolbarHistoryRecorder()
        var boundWindow: BrowserWindowState? = BrowserWindowState()
        weak var releasedBoundWindow = boundWindow
        let owner = NavigationToolbarContextHarness.makeOwner(
            browserManager: browserManager,
            history: history.owner
        )
        let context = owner.navigationHistoryContext(for: boundWindow!)
        boundWindow = nil

        XCTAssertNil(releasedBoundWindow)

        let targetURL = URL(string: "https://stale.example/path")!
        context.openURLInNewTab(targetURL, true, nil)
        context.openURLInCurrentTab(targetURL, nil)

        XCTAssertTrue(
            browserManager.regularTabCollectionOwner.allTabs(
                in: browserManager.spaceStateOwner.spaces
            ).isEmpty
        )
        XCTAssertTrue(history.loadedURLs.isEmpty)
    }

    func testNavigationHistoryNewWindowDelegatesURLs() async {
        let harness = NavigationToolbarContextHarness()
        let history = NavigationToolbarHistoryRecorder()
        history.registeredWindow = BrowserWindowState()
        let owner = harness.makeOwner(history: history.owner)
        let urls = [
            URL(string: "https://first.example")!,
            URL(string: "https://second.example")!,
        ]

        owner.navigationHistoryContext(for: harness.windowState)
            .openURLsInNewWindow(urls)

        for _ in 0..<20 where history.openedURLs.count != urls.count {
            await Task.yield()
        }

        XCTAssertEqual(history.createdWindowCount, 1)
        XCTAssertEqual(history.openedURLs, urls)
    }

    func testToolbarBackForwardActionsUseBoundWindow() {
        let harness = NavigationToolbarContextHarness()
        let history = NavigationToolbarHistoryRecorder()
        let webView = WKWebView()
        history.activePagesByWindowID[harness.windowState.id] = ActivePageResolution(
            source: .selectedTab,
            windowState: harness.windowState,
            tab: harness.tab,
            url: harness.tab.url,
            canonicalWebView: webView
        )
        let context = harness.makeOwner(history: history.owner)
            .navigationToolbarContext(for: harness.windowState)

        context.goBack()
        context.goForward()

        XCTAssertEqual(history.backwardWebViews, [ObjectIdentifier(webView)])
        XCTAssertEqual(history.forwardWebViews, [ObjectIdentifier(webView)])
    }

    func testToolbarReloadActionUsesBoundWindow() {
        let harness = NavigationToolbarContextHarness()
        let webView = NavigationToolbarReloadRecordingWebView()
        harness.register(webView, for: harness.tab)
        let context = harness.owner.navigationToolbarContext(
            for: harness.windowState
        )

        context.reload(harness.tab)

        XCTAssertEqual(webView.loadedURLs, [harness.tab.url])
    }
}

@MainActor
private final class NavigationToolbarContextHarness {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let space: Space
    let tab: Tab

    init() {
        browserManager = BrowserManager()
        let profile = Profile(name: "Toolbar")
        space = Space(name: "Toolbar", profileId: profile.id)
        windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)
        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browserManager.windowRegistry.register(windowState)
        browserManager.windowRegistry.setActive(windowState)

        tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://toolbar.example",
            in: space,
            activate: false
        )
        windowState.currentTabId = tab.id
    }

    var tabs: [Tab] {
        browserManager.regularTabCollectionOwner.tabs(in: space)
    }

    var owner: BrowserNavigationToolbarContextOwner {
        makeOwner(history: browserManager.historyBundle.historyNavigationOwner)
    }

    func makeOwner(
        history: BrowserHistoryNavigationOwner
    ) -> BrowserNavigationToolbarContextOwner {
        Self.makeOwner(browserManager: browserManager, history: history)
    }

    static func makeOwner(
        browserManager: BrowserManager,
        history: BrowserHistoryNavigationOwner
    ) -> BrowserNavigationToolbarContextOwner {
        BrowserNavigationToolbarContextOwner(
            windowTabs: browserManager.shellRuntime.windowTabs,
            webViews: browserManager.webViewRoutingService,
            dataServices: browserManager.dataServices,
            history: history,
            tabOpening: browserManager.tabOpening
        )
    }

    func register(_ webView: WKWebView, for tab: Tab) {
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: TrackedWebViewOwner(
                tabID: tab.id,
                windowID: windowState.id
            ),
            in: browserManager.webViewSessions,
            removeFromContainers: { _ in },
            installRuntimeObservations: { _ in },
            uninstallRuntimeObservationsIfUntracked: { _ in },
            pruneInvalidDeferredCommands: { _ in },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in },
            cleanupDisplacedWebView: { _, _ in }
        )
    }
}

@MainActor
private final class NavigationToolbarHistoryRecorder {
    var activePagesByWindowID: [UUID: ActivePageResolution] = [:]
    var registeredWindow: BrowserWindowState?
    private(set) var loadedURLs: [URL] = []
    private(set) var loadedWindows: [BrowserWindowState] = []
    private(set) var openedURLs: [URL] = []
    private(set) var createdWindowCount = 0
    private(set) var backwardWebViews: [ObjectIdentifier] = []
    private(set) var forwardWebViews: [ObjectIdentifier] = []

    var owner: BrowserHistoryNavigationOwner {
        BrowserHistoryNavigationOwner(
            activeWindow: { nil },
            activePage: { [weak self] window in
                self?.activePagesByWindowID[window.id]
            },
            openNativeBrowserSurface: { _, _, _, _ in },
            openNewTab: { [weak self] url, context in
                self?.openedURLs.append(URL(string: url)!)
                return Tab(
                    url: URL(string: url)!,
                    spaceId: context.preferredSpaceId,
                    loadsCachedFaviconOnInit: false
                )
            },
            loadCurrentPageURL: { [weak self] _, window, url in
                self?.loadedURLs.append(url)
                self?.loadedWindows.append(window)
            },
            windowIds: { [] },
            createNewWindow: { [weak self] in
                self?.createdWindowCount += 1
            },
            awaitNextRegisteredWindow: { [weak self] _ in
                self?.registeredWindow
            },
            scheduleRuntimeStatePersistence: { _ in },
            schedulePrepareVisibleWebViews: { _ in },
            refreshCompositor: { _ in },
            navigateBack: { [weak self] webView in
                self?.backwardWebViews.append(ObjectIdentifier(webView))
            },
            navigateForward: { [weak self] webView in
                self?.forwardWebViews.append(ObjectIdentifier(webView))
            }
        )
    }
}

@MainActor
private final class NavigationToolbarReloadRecordingWebView: WKWebView {
    private(set) var loadedURLs: [URL] = []

    override func load(_ request: URLRequest) -> WKNavigation? {
        if let url = request.url {
            loadedURLs.append(url)
        }
        return nil
    }
}
