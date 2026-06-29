@testable import Sumi
import XCTest

@MainActor
final class SettingsNavigationTests: XCTestCase {
    func testSidebarOrderingKeepsAboutLastAndHidesUserscripts() {
        XCTAssertEqual(
            SettingsTabs.ordered,
            [.general, .appearance, .downloads, .startup, .performance, .privacy, .profiles, .shortcuts, .extensions, .advanced, .about]
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

    func testNewTabSettingsDefaultAndPersistence() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        XCTAssertEqual(settings.newTabMode, .floatingBar)
        XCTAssertEqual(settings.newTabPageURLString, SumiNewTabPageURL.defaultURLString)

        settings.newTabMode = .specificPage
        settings.newTabPageURLString = "example.com"

        let reloaded = SumiSettingsService(userDefaults: harness.defaults)
        XCTAssertEqual(reloaded.newTabMode, .specificPage)
        XCTAssertEqual(reloaded.newTabPageURLString, "example.com")
        XCTAssertEqual(reloaded.resolvedNewTabPageURL.absoluteString, "https://example.com")
    }

    func testUnifiedSearchEnginesDefaultOrderAndTabSearchPriority() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.searchEngineId, SearchProvider.google.rawValue)
        XCTAssertTrue(settings.searchEngines.contains { $0.id == SearchProvider.google.rawValue })
        XCTAssertEqual(
            Array(settings.searchEngines.prefix(SearchProvider.allCases.count)).map(\.id),
            SearchProvider.allCases.map(\.rawValue)
        )
        XCTAssertEqual(settings.searchEngines[SearchProvider.allCases.count].name, "YouTube")

        let youtubeMatch = SumiSearchEngine.match(for: "y", in: settings.searchEngines)
        XCTAssertEqual(youtubeMatch?.name, "YouTube")

        let githubMatch = SumiSearchEngine.match(for: "g", in: settings.searchEngines)
        XCTAssertEqual(githubMatch?.name, "GitHub")
    }

    func testUnifiedSearchEngineDefaultCanUseSiteSearchEngine() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let youtube = settings.searchEngines.first { $0.name == "YouTube" }

        settings.searchEngineId = try! XCTUnwrap(youtube?.id)

        XCTAssertEqual(settings.resolvedSearchEngineDisplayName, "YouTube")
        XCTAssertEqual(
            normalizeURL("sumi browser", queryTemplate: settings.resolvedSearchEngineTemplate),
            "https://www.youtube.com/results?search_query=sumi%20browser"
        )
    }

    func testUnifiedSearchEnginesPersistCustomEntries() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let custom = SumiSearchEngine(
            id: "startpage",
            name: "Startpage",
            domain: "www.startpage.com",
            searchURLTemplate: "https://www.startpage.com/sp/search?query={query}",
            colorHex: "#666666",
            tabSearchEnabled: true
        )
        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.searchEngines.append(custom)
        settings.searchEngineId = custom.id

        let reloaded = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertTrue(reloaded.searchEngines.contains { $0.id == custom.id })
        XCTAssertEqual(reloaded.resolvedSearchEngineDisplayName, "Startpage")
        XCTAssertEqual(
            normalizeURL("privacy", queryTemplate: reloaded.resolvedSearchEngineTemplate),
            "https://www.startpage.com/sp/search?query=privacy"
        )
    }

    func testTabSearchMatchUsesFirstMatchingEnabledEngineInListOrder() {
        let github = SumiSearchEngine(
            id: "github",
            name: "GitHub",
            domain: "github.com",
            searchURLTemplate: "https://github.com/search?q={query}",
            tabSearchEnabled: true
        )
        let google = SumiSearchEngine(
            id: "google",
            name: "Google",
            domain: "google.com",
            searchURLTemplate: "https://www.google.com/search?q={query}",
            tabSearchEnabled: true
        )

        XCTAssertEqual(SumiSearchEngine.match(for: "g", in: [github, google])?.id, "github")
        XCTAssertEqual(SumiSearchEngine.match(for: "g", in: [google, github])?.id, "google")
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
            "Profiles"
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

    func testOpenSettingsTabReusesEphemeralSettingsSurfaceInIncognitoWindow() throws {
        let (browserManager, _, settings, windowState, space) = makeHarness()
        let ephemeralProfile = Profile.createEphemeral()
        windowState.isIncognito = true
        windowState.ephemeralProfile = ephemeralProfile
        windowState.currentProfileId = ephemeralProfile.id

        browserManager.openSettingsTab(selecting: .privacy, in: windowState)

        let firstSettingsTab = try XCTUnwrap(
            windowState.ephemeralTabs.first(where: \.representsSumiSettingsSurface)
        )
        XCTAssertEqual(firstSettingsTab.profileId, ephemeralProfile.id)
        XCTAssertEqual(firstSettingsTab.url, SettingsTabs.privacy.settingsSurfaceURL)
        XCTAssertEqual(firstSettingsTab.name, "Settings")
        XCTAssertEqual(windowState.currentTabId, firstSettingsTab.id)
        XCTAssertEqual(settings.currentSettingsTab, .privacy)
        XCTAssertTrue(browserManager.tabManager.tabs(in: space).filter(\.representsSumiSettingsSurface).isEmpty)

        browserManager.openSettingsTab(selecting: .about, in: windowState)

        let settingsTabs = windowState.ephemeralTabs.filter(\.representsSumiSettingsSurface)
        XCTAssertEqual(settingsTabs.count, 1)
        XCTAssertEqual(settingsTabs.first?.id, firstSettingsTab.id)
        XCTAssertEqual(firstSettingsTab.url, SettingsTabs.about.settingsSurfaceURL)
        XCTAssertEqual(windowState.currentTabId, firstSettingsTab.id)
        XCTAssertEqual(settings.currentSettingsTab, .about)
        XCTAssertTrue(browserManager.tabManager.tabs(in: space).filter(\.representsSumiSettingsSurface).isEmpty)
    }

    func testFloatingBarCurrentSettingsURLCommitAppliesPaneNavigation() {
        let (browserManager, _, settings, windowState, space) = makeHarness()
        let existing = browserManager.tabManager.createNewTab(
            url: SettingsTabs.general.settingsSurfaceURL.absoluteString,
            in: space,
            activate: false
        )
        browserManager.selectTab(existing, in: windowState, loadPolicy: .deferred)
        settings.currentSettingsTab = .general
        settings.extensionsSettingsSubPane = .userScripts

        browserManager.commitFloatingBarSuggestion(
            SearchManager.SearchSuggestion(
                text: "sumi://settings?pane=extensions",
                type: .url
            ),
            in: windowState,
            navigatesCurrentTab: true
        )

        XCTAssertEqual(existing.url, SettingsTabs.extensions.settingsSurfaceURL)
        XCTAssertEqual(windowState.currentTabId, existing.id)
        XCTAssertEqual(settings.currentSettingsTab, .extensions)
        XCTAssertEqual(settings.extensionsSettingsSubPane, .extensions)
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
