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
        let tab = Tab(url: historyURL, skipFaviconFetch: true)

        XCTAssertTrue(tab.representsSumiHistorySurface)
        XCTAssertTrue(tab.representsSumiInternalSurface)
        XCTAssertTrue(tab.representsSumiNativeSurface)
        XCTAssertTrue(tab.representsSumiNativeSurface)
        XCTAssertFalse(tab.requiresPrimaryWebView)
        XCTAssertTrue(tab.usesChromeThemedTemplateFavicon)
    }

    func testOpenHistoryTabCreatesNewBrowserTabEachTime() {
        let (browserManager, _, windowState, space) = makeHarness()

        browserManager.openHistoryTab(in: windowState)
        browserManager.openHistoryTab(selecting: .older, in: windowState)

        let historyTabs = browserManager.tabManager.tabs(in: space).filter(\.representsSumiHistorySurface)
        XCTAssertEqual(historyTabs.count, 2)
        XCTAssertEqual(
            historyTabs.last?.url,
            SumiSurface.historySurfaceURL(rangeQuery: HistoryRange.older.paneQueryValue)
        )
        XCTAssertEqual(windowState.currentTabId, historyTabs.last?.id)
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
