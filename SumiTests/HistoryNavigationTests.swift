import WebKit
import XCTest

@testable import Sumi

@MainActor
final class HistoryNavigationTests: XCTestCase {
    func testOpenHistoryTabCreatesSelectedHistorySurface() {
        let (browserManager, _, windowState, space) = makeHarness()

        browserManager.historyNavigationOwner.openHistoryTab(in: windowState)

        let historyTabs = browserManager.tabManager.tabs(in: space).filter(\.representsSumiHistorySurface)
        XCTAssertEqual(historyTabs.count, 1)
        XCTAssertEqual(
            historyTabs.first?.url,
            SumiSurface.historySurfaceURL(rangeQuery: HistoryRange.all.paneQueryValue)
        )
        XCTAssertEqual(historyTabs.first?.name, "History")
        XCTAssertEqual(windowState.currentTabId, historyTabs.first?.id)
    }

    func testHistorySurfaceIsNativeBrowserTab() {
        let historyURL = SumiSurface.historySurfaceURL(
            rangeQuery: HistoryRange.all.paneQueryValue
        )
        let tab = Tab(url: historyURL)

        XCTAssertTrue(tab.representsSumiHistorySurface)
        XCTAssertTrue(tab.representsSumiInternalSurface)
        XCTAssertTrue(tab.representsSumiNativeSurface)
        XCTAssertTrue(tab.representsSumiNativeSurface)
        XCTAssertFalse(tab.requiresPrimaryWebView)
        XCTAssertTrue(tab.usesChromeThemedTemplateFavicon)
    }

    func testOpenHistoryTabReusesExistingHistorySurface() throws {
        let (browserManager, _, windowState, space) = makeHarness()

        browserManager.historyNavigationOwner.openHistoryTab(in: windowState)
        let firstHistoryTab = try XCTUnwrap(
            browserManager.tabManager.tabs(in: space).first(where: \.representsSumiHistorySurface)
        )

        browserManager.historyNavigationOwner.openHistoryTab(selecting: .older, in: windowState)

        let historyTabs = browserManager.tabManager.tabs(in: space).filter(\.representsSumiHistorySurface)
        XCTAssertEqual(historyTabs.count, 1)
        XCTAssertEqual(historyTabs.first?.id, firstHistoryTab.id)
        XCTAssertEqual(
            historyTabs.first?.url,
            SumiSurface.historySurfaceURL(rangeQuery: HistoryRange.older.paneQueryValue)
        )
        XCTAssertEqual(windowState.currentTabId, firstHistoryTab.id)
    }

    func testOpenHistoryURLInCurrentTabRoutesThroughWindowScopedLoader() throws {
        let windowState = BrowserWindowState()
        let currentTab = Tab(
            url: try XCTUnwrap(URL(string: "https://old.example")),
            name: "Old",
            loadsCachedFaviconOnInit: false
        )
        let targetURL = try XCTUnwrap(URL(string: "https://target.example"))
        let harness = HistoryNavigationOwnerHarness(activePageTab: currentTab)
        let owner = harness.makeOwner()

        owner.openHistoryURL(targetURL, in: windowState, preferredOpenMode: .currentTab)

        XCTAssertEqual(
            harness.loadedCurrentPages,
            [.init(tabId: currentTab.id, windowId: windowState.id, url: targetURL)]
        )
    }

    func testReplacingHistorySurfaceRoutesThroughWindowScopedLoader() throws {
        let windowState = BrowserWindowState()
        let historyTab = Tab(
            url: SumiSurface.historySurfaceURL(rangeQuery: HistoryRange.all.paneQueryValue),
            name: "History",
            loadsCachedFaviconOnInit: false
        )
        let targetURL = try XCTUnwrap(URL(string: "https://target.example"))
        let harness = HistoryNavigationOwnerHarness(activePageTab: historyTab)
        let owner = harness.makeOwner()

        owner.openHistoryURL(targetURL, in: windowState, preferredOpenMode: .currentTab)

        XCTAssertEqual(
            harness.loadedCurrentPages,
            [.init(tabId: historyTab.id, windowId: windowState.id, url: targetURL)]
        )
        XCTAssertEqual(historyTab.name, "target.example")
    }

    func testGoBackInSpecificWindowUsesThatWindowWebView() {
        let activeWindow = BrowserWindowState()
        let targetWindow = BrowserWindowState()
        let activeTab = makeTab("https://active.example")
        let targetTab = makeTab("https://target.example")
        let activeWebView = HistoryNavigationRecordingWebView(canGoBack: true)
        let targetWebView = HistoryNavigationRecordingWebView(canGoBack: true)
        let harness = HistoryNavigationOwnerHarness(activeWindow: activeWindow)
        harness.activePageTabsByWindowId = [
            activeWindow.id: activeTab,
            targetWindow.id: targetTab,
        ]
        harness.webViewsByWindowId = [
            activeWindow.id: activeWebView,
            targetWindow.id: targetWebView,
        ]
        let owner = harness.makeOwner()

        owner.goBack(in: targetWindow)

        XCTAssertEqual(harness.navigatedBackWebViewIDs, [ObjectIdentifier(targetWebView)])
    }

    func testGoBackInActiveWindowDelegatesThroughScopedActiveWindow() {
        let activeWindow = BrowserWindowState()
        let inactiveWindow = BrowserWindowState()
        let activeTab = makeTab("https://active.example")
        let inactiveTab = makeTab("https://inactive.example")
        let activeWebView = HistoryNavigationRecordingWebView(canGoBack: true)
        let inactiveWebView = HistoryNavigationRecordingWebView(canGoBack: true)
        let harness = HistoryNavigationOwnerHarness(activeWindow: activeWindow)
        harness.activePageTabsByWindowId = [
            activeWindow.id: activeTab,
            inactiveWindow.id: inactiveTab,
        ]
        harness.webViewsByWindowId = [
            activeWindow.id: activeWebView,
            inactiveWindow.id: inactiveWebView,
        ]
        let owner = harness.makeOwner()

        owner.goBackInActiveWindow()

        XCTAssertEqual(harness.navigatedBackWebViewIDs, [ObjectIdentifier(activeWebView)])
    }

    private func makeHarness() -> (BrowserManager, WindowRegistry, BrowserWindowState, Space) {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.webViewCoordinator = WebViewCoordinator()
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.historyManager.switchProfile(profile.id)
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (browserManager, windowRegistry, windowState, space)
    }

    private func makeTab(_ url: String) -> Tab {
        Tab(
            url: URL(string: url)!,
            name: url,
            loadsCachedFaviconOnInit: false
        )
    }
}

@MainActor
private final class HistoryNavigationOwnerHarness {
    struct LoadedCurrentPage: Equatable {
        let tabId: UUID
        let windowId: UUID
        let url: URL
    }

    var activeWindow: BrowserWindowState?
    var activePageTab: Tab?
    var activePageTabsByWindowId: [UUID: Tab] = [:]
    var webViewsByWindowId: [UUID: WKWebView] = [:]
    var loadedCurrentPages: [LoadedCurrentPage] = []
    var navigatedBackWebViewIDs: [ObjectIdentifier] = []
    var navigatedForwardWebViewIDs: [ObjectIdentifier] = []

    init(activeWindow: BrowserWindowState? = nil, activePageTab: Tab? = nil) {
        self.activeWindow = activeWindow
        self.activePageTab = activePageTab
    }

    func makeOwner() -> BrowserHistoryNavigationOwner {
        BrowserHistoryNavigationOwner(
            dependencies: BrowserHistoryNavigationOwner.Dependencies(
                activeWindow: { [weak self] in self?.activeWindow },
                activePageTab: { [weak self] windowState in
                    self?.activePageTabsByWindowId[windowState.id] ?? self?.activePageTab
                },
                activePageWebView: { [weak self] windowState in
                    self?.webViewsByWindowId[windowState.id]
                },
                webView: { [weak self] _, windowId in
                    self?.webViewsByWindowId[windowId]
                },
                openNativeBrowserSurface: { _, _, _, _ in /* No-op. */ },
                openNewTab: { _, _ in nil },
                loadCurrentPageURL: { [weak self] tab, windowState, url in
                    self?.loadedCurrentPages.append(
                        .init(tabId: tab.id, windowId: windowState.id, url: url)
                    )
                },
                windowIds: { [] },
                createNewWindow: { /* No-op. */ },
                awaitNextRegisteredWindow: { _ in nil },
                scheduleRuntimeStatePersistence: { _ in /* No-op. */ },
                schedulePrepareVisibleWebViews: { _ in /* No-op. */ },
                refreshCompositor: { _ in /* No-op. */ },
                navigateBack: { [weak self] webView in
                    self?.navigatedBackWebViewIDs.append(ObjectIdentifier(webView))
                },
                navigateForward: { [weak self] webView in
                    self?.navigatedForwardWebViewIDs.append(ObjectIdentifier(webView))
                }
            )
        )
    }
}

private final class HistoryNavigationRecordingWebView: WKWebView {
    private let canGoBackValue: Bool
    private let canGoForwardValue: Bool

    init(canGoBack: Bool = false, canGoForward: Bool = false) {
        canGoBackValue = canGoBack
        canGoForwardValue = canGoForward
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canGoBack: Bool {
        canGoBackValue
    }

    override var canGoForward: Bool {
        canGoForwardValue
    }
}
