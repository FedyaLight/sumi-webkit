import XCTest
@testable import Sumi

@MainActor
final class SettingsNavigationTests: XCTestCase {
    func testSidebarOrderingKeepsAboutLastAndHidesUserscripts() {
        XCTAssertEqual(
            SettingsTabs.ordered,
            [.general, .appearance, .performance, .privacy, .profiles, .shortcuts, .extensions, .advanced, .about]
        )
        XCTAssertEqual(SettingsTabs.ordered.last, .about)
        XCTAssertFalse(SettingsTabs.ordered.contains(.userScripts))
    }

    func testPerformancePaneQueryRoundTripsThroughSettingsSurfaceURL() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.currentSettingsTab = .performance

        XCTAssertEqual(SettingsTabs(paneQueryValue: "performance"), .performance)
        XCTAssertEqual(
            settings.settingsSurfaceURLForCurrentNavigation(),
            SettingsTabs.performance.settingsSurfaceURL
        )

        settings.currentSettingsTab = .general
        settings.applyNavigationFromSettingsSurfaceURL(SettingsTabs.performance.settingsSurfaceURL)

        XCTAssertEqual(settings.currentSettingsTab, .performance)
    }

    func testAboutPaneQueryRoundTripsThroughSettingsSurfaceURL() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.currentSettingsTab = .about

        XCTAssertEqual(SettingsTabs(paneQueryValue: "about"), .about)
        XCTAssertEqual(settings.settingsSurfaceURLForCurrentNavigation(), SettingsTabs.about.settingsSurfaceURL)

        settings.currentSettingsTab = .appearance
        settings.applyNavigationFromSettingsSurfaceURL(SettingsTabs.about.settingsSurfaceURL)

        XCTAssertEqual(settings.currentSettingsTab, .about)
    }

    func testSettingsSurfaceRemainsNativeNonWebSurface() {
        let tab = Tab(url: SettingsTabs.about.settingsSurfaceURL)

        XCTAssertTrue(tab.representsSumiSettingsSurface)
        XCTAssertTrue(tab.representsSumiInternalSurface)
        XCTAssertTrue(tab.representsSumiNativeSurface)
        XCTAssertTrue(tab.usesChromeThemedTemplateFavicon)
    }

    func testOpenSettingsTabSelectsAboutSurface() {
        let (browserManager, _, settings, windowState, space) = makeHarness()

        browserManager.openSettingsTab(selecting: .about, in: windowState)

        let settingsTabs = browserManager.tabManager.tabs(in: space).filter(\.representsSumiSettingsSurface)
        XCTAssertEqual(settingsTabs.count, 1)
        XCTAssertEqual(settingsTabs.first?.url, SettingsTabs.about.settingsSurfaceURL)
        XCTAssertEqual(windowState.currentTabId, settingsTabs.first?.id)
        XCTAssertEqual(settings.currentSettingsTab, .about)
    }

    func testOpenSettingsTabReusesExistingSettingsSurfaceForAbout() {
        let (browserManager, _, settings, windowState, space) = makeHarness()
        let existing = browserManager.tabManager.createNewTab(
            url: SettingsTabs.general.settingsSurfaceURL.absoluteString,
            in: space,
            activate: false
        )

        browserManager.openSettingsTab(selecting: .about, in: windowState)

        let settingsTabs = browserManager.tabManager.tabs(in: space).filter(\.representsSumiSettingsSurface)
        XCTAssertEqual(settingsTabs.count, 1)
        XCTAssertEqual(settingsTabs.first?.id, existing.id)
        XCTAssertEqual(existing.url, SettingsTabs.about.settingsSurfaceURL)
        XCTAssertEqual(windowState.currentTabId, existing.id)
        XCTAssertEqual(settings.currentSettingsTab, .about)
    }

    private func makeHarness() -> (BrowserManager, WindowRegistry, SumiSettingsService, BrowserWindowState, Space) {
        let harness = TestDefaultsHarness()
        addTeardownBlock {
            harness.reset()
        }

        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let space = Space(name: "Primary")
        let windowState = BrowserWindowState()

        browserManager.windowRegistry = windowRegistry
        browserManager.sumiSettings = settings
        browserManager.tabManager.sumiSettings = settings
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (browserManager, windowRegistry, settings, windowState, space)
    }
}
