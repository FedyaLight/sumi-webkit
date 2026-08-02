import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class SettingsNavigationTests: XCTestCase {
    func testSettingsSceneOwnsSingleApplicationMenuCommand() throws {
        let appSource = try repositorySource("App/SumiApp.swift")
        let commandsSource = try repositorySource("App/SumiCommands.swift")

        XCTAssertTrue(appSource.contains("Settings {"))
        XCTAssertFalse(commandsSource.contains("CommandGroup(replacing: .appSettings)"))
    }

    func testSettingsNativeSurfaceStructureAvoidsDuplicateChromeAndNestedScrolling() throws {
        let windowSource = try settingsSource("SumiSettingsSceneRootView.swift")
        XCTAssertTrue(windowSource.contains(".navigationTitle(toolbarOwner.presentation.title)"))
        XCTAssertFalse(windowSource.contains("view.window?.title = presentation.title"))
        XCTAssertFalse(windowSource.contains("toolbarTitleLabel"))
        XCTAssertFalse(windowSource.contains("private let navigationControl = NSSegmentedControl()"))
        XCTAssertFalse(windowSource.contains("private let headerView = NSVisualEffectView()"))
        XCTAssertTrue(windowSource.contains("item.isNavigational = true"))
        XCTAssertFalse(windowSource.contains(".toggleSidebar,"))

        let componentsSource = try settingsSource("SettingsComponents.swift")
        XCTAssertFalse(componentsSource.contains("struct SettingsPopUpButton"))
        XCTAssertTrue(componentsSource.contains(".pickerStyle(.menu)"))

        let startupSource = try settingsSource("Tabs/Startup.swift")
        XCTAssertTrue(startupSource.contains(".settingsMenuPicker"))
        XCTAssertFalse(startupSource.contains(".pickerStyle(.radioGroup)"))

        let searchEnginesSource = try settingsSource("Tabs/GeneralSearchEnginesSettingsSection.swift")
        XCTAssertFalse(searchEnginesSource.contains("NSScrollView"))
        XCTAssertTrue(searchEnginesSource.contains("SumiSearchEngineTableLayout.preferredHeight"))
    }

    func testAboutSettingsAvoidsSidebarOnlyEnvironmentDependencies() throws {
        let aboutSource = try settingsSource("Tabs/About.swift")

        XCTAssertFalse(aboutSource.contains(".sidebarHover"))
        XCTAssertFalse(aboutSource.contains("BrowserWindowState"))
    }

    func testSidebarOrderingKeepsAboutLast() {
        XCTAssertEqual(
            SettingsTabs.ordered,
            [.general, .appearance, .downloads, .startup, .performance, .privacy, .profiles, .shortcuts, .extensions, .advanced, .about]
        )
        XCTAssertEqual(SettingsTabs.ordered.last, .about)
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

        XCTAssertEqual(settings.newTabMode, .commandPalette)
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
        XCTAssertEqual(SumiSearchEngine.match(for: "y", in: settings.searchEngines)?.name, "YouTube")
        XCTAssertEqual(SumiSearchEngine.match(for: "g", in: settings.searchEngines)?.name, "GitHub")
    }

    func testUnifiedSearchEngineDefaultCanUseSiteSearchEngine() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let youtube = try XCTUnwrap(settings.searchEngines.first { $0.name == "YouTube" })

        settings.searchEngineId = youtube.id

        XCTAssertEqual(settings.resolvedSearchEngineDisplayName, "YouTube")
        XCTAssertEqual(
            normalizeURL("sumi browser", queryTemplate: settings.resolvedSearchEngineTemplate),
            "https://www.youtube.com/results?search_query=sumi+browser"
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

    func testTabSearchURLEncodesPerTokenPosition() {
        let engines = SumiSearchEngine.defaultEngines()
        func url(_ id: String, _ query: String) -> String? {
            engines.first { $0.id == id }?.searchURL(for: query)?.absoluteString
        }

        XCTAssertEqual(url("site.youtube", "daft punk"), "https://www.youtube.com/results?search_query=daft+punk")
        XCTAssertEqual(url("site.spotify", "daft punk"), "https://open.spotify.com/search/daft%20punk")
        XCTAssertEqual(url("site.spotify", "ac/dc"), "https://open.spotify.com/search/ac%2Fdc")
        XCTAssertEqual(url("site.github", "sort & filter"), "https://github.com/search?q=sort+%26+filter")
    }

    func testStartupPageURLNormalizationAndValidation() {
        XCTAssertEqual(SumiStartupPageURL.normalizedURLString(from: "example.com"), "https://example.com")
        XCTAssertEqual(
            SumiStartupPageURL.normalizedURLString(from: "https://example.com/path"),
            "https://example.com/path"
        )
        XCTAssertEqual(SumiStartupPageURL.normalizedURLString(from: "about:blank"), "about:blank")
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

    func testSettingsNavigationPresentsWindowAndSelectsPane() {
        let navigation = SettingsNavigationOwner()
        var presentationCount = 0
        navigation.installPresentationAction { presentationCount += 1 }

        navigation.openSettings(selecting: .extensions)

        XCTAssertEqual(navigation.currentSettingsTab, .extensions)
        XCTAssertEqual(presentationCount, 1)
    }

    func testSettingsNavigationOpensFilteredSiteSettings() {
        let navigation = SettingsNavigationOwner()
        let filter = SumiSettingsSiteSettingsFilter(
            requestingOriginIdentity: "https://example.com",
            topOriginIdentity: "https://example.com",
            displayDomain: "example.com"
        )

        navigation.openSiteSettings(filter: filter)

        XCTAssertEqual(navigation.currentSettingsTab, .privacy)
        XCTAssertEqual(navigation.privacySettingsRoute, .siteSettings(filter))
    }

    func testOpeningRegularPrivacyPaneLeavesSiteSettingsRoute() {
        let navigation = SettingsNavigationOwner()
        navigation.openSiteSettings(filter: nil)

        navigation.openSettings(selecting: .privacy)

        XCTAssertEqual(navigation.privacySettingsRoute, .overview)
    }

    func testSettingsToolbarPresentationTracksNestedNavigationActions() {
        let toolbar = SettingsWindowToolbarOwner()
        var backCount = 0
        var forwardCount = 0

        toolbar.show(
            title: "Site Settings",
            backAction: { backCount += 1 },
            forwardAction: { forwardCount += 1 }
        )

        XCTAssertEqual(toolbar.presentation.title, "Site Settings")
        XCTAssertTrue(toolbar.presentation.canGoBack)
        XCTAssertTrue(toolbar.presentation.canGoForward)

        toolbar.goBack()
        toolbar.goForward()
        XCTAssertEqual(backCount, 1)
        XCTAssertEqual(forwardCount, 1)

        toolbar.showRoot(title: "Privacy & Security")
        XCTAssertEqual(toolbar.presentation.title, "Privacy & Security")
        XCTAssertFalse(toolbar.presentation.canGoBack)
        XCTAssertFalse(toolbar.presentation.canGoForward)
    }

    func testSettingsPaneDescriptorsCoverVisiblePanes() {
        XCTAssertEqual(SettingsPaneDescriptor.all.map(\.tab), SettingsTabs.ordered)
        XCTAssertEqual(Set(SettingsPaneDescriptor.all.map(\.id)), Set(SettingsTabs.ordered))
        XCTAssertEqual(SettingsPaneDescriptor.descriptor(for: .privacy).title, "Privacy & Security")
    }

    func testSettingsPaneSearchMatchesTitlesSubtitlesAndKeywords() {
        XCTAssertEqual(SettingsPaneDescriptor.filtered(by: "tracker").map(\.tab), [.privacy])
        XCTAssertEqual(SettingsPaneDescriptor.filtered(by: "custom delay").map(\.tab), [.performance])
        XCTAssertEqual(SettingsPaneDescriptor.filtered(by: "previous session").map(\.tab), [.startup])
        XCTAssertTrue(SettingsPaneDescriptor.filtered(by: "safari extension").map(\.tab).contains(.extensions))
        XCTAssertTrue(SettingsPaneDescriptor.filtered(by: "no matching settings").isEmpty)
    }

    func testOpeningSettingsDoesNotCreateBrowserTab() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let browserManager = BrowserManager()
        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let space = Space(name: "Primary")
        browserManager.sumiSettings = settings
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        browserManager.urlBarBundle.settingsNavigation.openSettings(selecting: .about)

        XCTAssertEqual(settings.currentSettingsTab, .about)
        XCTAssertTrue(browserManager.regularTabCollectionOwner.tabs(in: space).isEmpty)
    }

    private func settingsSource(_ relativePath: String) throws -> String {
        try repositorySource("Sumi/Components/Settings/\(relativePath)")
    }

    private func repositorySource(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
