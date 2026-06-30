import XCTest

@testable import Sumi

@MainActor
final class HistoryNavigationTests: XCTestCase {
    func testOpenHistoryTabCreatesSelectedHistorySurface() {
        let (browserManager, _, windowState, space) = makeHarness()

        browserManager.openHistoryTab(in: windowState)

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

        browserManager.openHistoryTab(in: windowState)
        let firstHistoryTab = try XCTUnwrap(
            browserManager.tabManager.tabs(in: space).first(where: \.representsSumiHistorySurface)
        )

        browserManager.openHistoryTab(selecting: .older, in: windowState)

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

    private func makeHarness() -> (BrowserManager, WindowRegistry, BrowserWindowState, Space) {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

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
    var loadedCurrentPages: [LoadedCurrentPage] = []

    init(activeWindow: BrowserWindowState? = nil, activePageTab: Tab? = nil) {
        self.activeWindow = activeWindow
        self.activePageTab = activePageTab
    }

    func makeOwner() -> BrowserHistoryNavigationOwner {
        BrowserHistoryNavigationOwner(
            dependencies: BrowserHistoryNavigationOwner.Dependencies(
                activeWindow: { [weak self] in self?.activeWindow },
                activePageTab: { [weak self] _ in self?.activePageTab },
                activePageWebView: { _ in nil },
                webView: { _, _ in nil },
                openNativeBrowserSurface: { _, _, _, _ in },
                openNewTab: { _, _ in nil },
                loadCurrentPageURL: { [weak self] tab, windowState, url in
                    self?.loadedCurrentPages.append(
                        .init(tabId: tab.id, windowId: windowState.id, url: url)
                    )
                },
                windowIds: { [] },
                createNewWindow: {},
                awaitNextRegisteredWindow: { _ in nil },
                scheduleRuntimeStatePersistence: { _ in },
                schedulePrepareVisibleWebViews: { _ in },
                refreshCompositor: { _ in }
            )
        )
    }
}
