import XCTest
@testable import Sumi

@MainActor
final class SettingsNavigationTests: XCTestCase {
    func testSidebarOrderingKeepsAboutLastAndHidesUserscripts() {
        XCTAssertEqual(
            SettingsTabs.ordered,
            [.general, .startup, .appearance, .performance, .privacy, .profiles, .shortcuts, .extensions, .advanced, .about]
        )
        XCTAssertEqual(SettingsTabs.ordered.last, .about)
        XCTAssertFalse(SettingsTabs.ordered.contains(.userScripts))
    }

    func testStartupSettingsDefaultAndPersistence() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        XCTAssertEqual(settings.startupMode, .restorePreviousSession)
        XCTAssertEqual(settings.startupPageURLString, SumiStartupPageURL.defaultURLString)

        settings.startupMode = .specificPage
        settings.startupPageURLString = "example.com"

        let reloaded = SumiSettingsService(userDefaults: harness.defaults)
        XCTAssertEqual(reloaded.startupMode, .specificPage)
        XCTAssertEqual(reloaded.startupPageURLString, "example.com")
        XCTAssertEqual(reloaded.resolvedStartupPageURL.absoluteString, "https://example.com")
    }

    func testStartupPageURLNormalizationAndValidation() {
        XCTAssertEqual(
            SumiStartupPageURL.normalizedURLString(from: "example.com"),
            "https://example.com"
        )
        XCTAssertEqual(
            SumiStartupPageURL.normalizedURLString(from: "https://example.com/path"),
            "https://example.com/path"
        )
        XCTAssertEqual(
            SumiStartupPageURL.normalizedURLString(from: "about:blank"),
            "about:blank"
        )
        XCTAssertEqual(
            SumiStartupPageURL.normalizedURLString(from: "sumi://settings?pane=startup"),
            "sumi://settings?pane=startup"
        )
        XCTAssertNil(SumiStartupPageURL.normalizedURLString(from: "plain search text"))
        XCTAssertNil(SumiStartupPageURL.normalizedURLString(from: "ftp://example.com"))
        XCTAssertNil(SumiStartupPageURL.normalizedURLString(from: "https://"))
        XCTAssertEqual(SumiStartupPageURL.runtimeURL(from: "plain search text"), SumiSurface.emptyTabURL)
        XCTAssertNotNil(SumiStartupPageURL.validationMessage(for: "plain search text"))
    }

    func testAllVisiblePaneQueriesRoundTripThroughSettingsSurfaceURL() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)

        for pane in SettingsTabs.ordered {
            settings.currentSettingsTab = pane

            XCTAssertEqual(SettingsTabs(paneQueryValue: pane.paneQueryValue), pane)
            XCTAssertEqual(
                settings.settingsSurfaceURLForCurrentNavigation(),
                pane.settingsSurfaceURL
            )

            settings.currentSettingsTab = .general
            settings.applyNavigationFromSettingsSurfaceURL(pane.settingsSurfaceURL)

            XCTAssertEqual(settings.currentSettingsTab, pane)
        }
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

    func testStartupPaneQueryRoutesThroughSettingsSurfaceURL() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let url = URL(string: "sumi://settings?pane=startup")!

        settings.applyNavigationFromSettingsSurfaceURL(url)

        XCTAssertEqual(settings.currentSettingsTab, .startup)
        XCTAssertEqual(SettingsTabs(paneQueryValue: "startup"), .startup)
        XCTAssertEqual(SettingsTabs.startup.settingsSurfaceURL, url)
    }

    func testPrivacySiteSettingsRouteRoundTripsThroughSettingsSurfaceURL() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.currentSettingsTab = .privacy
        settings.privacySettingsRoute = .siteSettings(
            SumiSettingsSiteSettingsFilter(
                requestingOriginIdentity: "https://example.com",
                topOriginIdentity: "https://example.com",
                displayDomain: "example.com"
            )
        )

        let url = settings.settingsSurfaceURLForCurrentNavigation()
        XCTAssertEqual(url.scheme, "sumi")
        XCTAssertEqual(url.host, "settings")
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(queryItems.first { $0.name == "section" }?.value, "siteSettings")
        XCTAssertEqual(queryItems.first { $0.name == "origin" }?.value, "https://example.com")

        settings.currentSettingsTab = .general
        settings.privacySettingsRoute = .overview
        settings.applyNavigationFromSettingsSurfaceURL(url)

        XCTAssertEqual(settings.currentSettingsTab, .privacy)
        XCTAssertTrue(settings.privacySettingsRoute.isSiteSettings)
        XCTAssertEqual(
            settings.privacySettingsRoute.siteSettingsFilter?.requestingOriginIdentity,
            "https://example.com"
        )
    }

    func testSettingsSurfaceRemainsNativeNonWebSurface() {
        let tab = Tab(url: SettingsTabs.about.settingsSurfaceURL)

        XCTAssertTrue(tab.representsSumiSettingsSurface)
        XCTAssertTrue(tab.representsSumiInternalSurface)
        XCTAssertTrue(tab.representsSumiNativeSurface)
        XCTAssertTrue(tab.usesChromeThemedTemplateFavicon)
    }

    func testSettingsPaneDescriptorsCoverVisiblePanes() {
        XCTAssertEqual(
            SettingsPaneDescriptor.all.map(\.tab),
            SettingsTabs.ordered
        )
        XCTAssertEqual(
            Set(SettingsPaneDescriptor.all.map(\.id)),
            Set(SettingsTabs.ordered)
        )
        XCTAssertEqual(
            SettingsPaneDescriptor.descriptor(for: .privacy).title,
            "Privacy & Security"
        )
        XCTAssertEqual(
            SettingsPaneDescriptor.descriptor(for: .profiles).title,
            "Profiles & Spaces"
        )
    }

    func testSettingsPaneSearchMatchesTitlesSubtitlesAndKeywords() {
        XCTAssertEqual(
            SettingsPaneDescriptor.filtered(by: "tracker").map(\.tab),
            [.privacy]
        )
        XCTAssertEqual(
            SettingsPaneDescriptor.filtered(by: "custom delay").map(\.tab),
            [.performance]
        )
        XCTAssertEqual(
            SettingsPaneDescriptor.filtered(by: "previous session").map(\.tab),
            [.startup]
        )
        XCTAssertTrue(
            SettingsPaneDescriptor.filtered(by: "safari extension").map(\.tab).contains(.extensions)
        )
        XCTAssertEqual(
            SettingsPaneDescriptor.filtered(by: "no matching settings").count,
            0
        )
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
