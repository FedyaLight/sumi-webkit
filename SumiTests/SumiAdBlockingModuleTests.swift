import BrowserServicesKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAdBlockingModuleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testCleanInstallDefaultsAdBlockingDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)
        let module = SumiAdBlockingModule(moduleRegistry: registry)

        XCTAssertFalse(registry.isEnabled(.adBlocking))
        XCTAssertNil(harness.defaults.object(forKey: store.key(for: .adBlocking)))
        XCTAssertFalse(module.isEnabled)
        XCTAssertEqual(module.status, .disabled)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testEnableDisablePersistsWithoutCreatingRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)
        let module = SumiAdBlockingModule(moduleRegistry: registry)

        module.setEnabled(true)

        XCTAssertTrue(SumiModuleRegistry(settingsStore: store).isEnabled(.adBlocking))
        XCTAssertEqual(module.status, .enabledButEngineUnavailable)
        XCTAssertFalse(module.hasLoadedRuntime)

        module.setEnabled(false)

        XCTAssertFalse(SumiModuleRegistry(settingsStore: store).isEnabled(.adBlocking))
        XCTAssertEqual(module.status, .disabled)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testAdBlockingStateIsIndependentFromTrackingProtectionState() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )

        registry.enable(.trackingProtection)
        XCTAssertTrue(registry.isEnabled(.trackingProtection))
        XCTAssertFalse(registry.isEnabled(.adBlocking))

        registry.enable(.adBlocking)
        XCTAssertTrue(registry.isEnabled(.trackingProtection))
        XCTAssertTrue(registry.isEnabled(.adBlocking))

        registry.disable(.trackingProtection)
        XCTAssertFalse(registry.isEnabled(.trackingProtection))
        XCTAssertTrue(registry.isEnabled(.adBlocking))
    }

    func testDisabledAccessorsReturnEmptyNoOpState() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let module = SumiAdBlockingModule(moduleRegistry: registry)
        let decision = module.normalTabDecision(
            for: URL(string: "https://www.example.com/page")!
        )

        XCTAssertEqual(module.status, .disabled)
        XCTAssertEqual(module.assetsIfAvailable(), .empty)
        XCTAssertEqual(decision.status, .disabled)
        XCTAssertEqual(decision.assets, .empty)
        XCTAssertTrue(decision.assets.isEmpty)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testEnabledShellReportsEngineUnavailableAndStillReturnsEmptyAssets() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let module = SumiAdBlockingModule(moduleRegistry: registry)
        let decision = module.normalTabDecision(
            for: URL(string: "https://ads.example.com/page")!
        )

        XCTAssertTrue(module.isEnabled)
        XCTAssertEqual(module.status, .enabledButEngineUnavailable)
        XCTAssertEqual(module.assetsIfAvailable(), .empty)
        XCTAssertEqual(decision.status, .enabledButEngineUnavailable)
        XCTAssertEqual(decision.assets.contentRuleListIdentifiers.count, 0)
        XCTAssertEqual(decision.assets.scriptSources.count, 0)
        XCTAssertEqual(decision.assets.scriptMessageHandlerNames.count, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testBrowserManagerStartupWithAdBlockingDisabledDoesNotCreateRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let module = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertFalse(browserManager.adBlockingModule.isEnabled)
        XCTAssertFalse(browserManager.adBlockingModule.hasLoadedRuntime)
    }

    func testOpeningSettingsWithAdBlockingDisabledDoesNotReferenceRuntimeShell() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let model = SumiSettingsModuleToggleModel(
            descriptor: .adBlocking,
            registry: registry
        )

        XCTAssertFalse(model.isEnabled)

        let privacySource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")
        let togglesSource = try Self.source(named: "Sumi/Components/Settings/SumiSettingsModuleToggles.swift")

        XCTAssertTrue(privacySource.contains("SumiSettingsModuleToggleGate(descriptor: .adBlocking)"))
        XCTAssertFalse(privacySource.contains("SumiAdBlockingModule"))
        XCTAssertFalse(privacySource.contains("sumiAdBlockingModule"))
        XCTAssertFalse(togglesSource.contains("SumiAdBlockingModule"))
        XCTAssertFalse(togglesSource.contains("normalTabDecision("))
        XCTAssertFalse(togglesSource.contains("assetsIfAvailable("))
    }

    func testNormalTabCreationWithAdBlockingDisabledAttachesNoAdBlockingAssets() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let module = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/ad-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let webView = try XCTUnwrap(tab.existingWebView)
        let controller = try XCTUnwrap(webView.configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertEqual(module.normalTabDecision(for: tab.url).assets, .empty)
        assertNoAdBlockingScriptsOrHandlers(in: webView.configuration.userContentController)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testNormalTabCreationWithAdBlockingEnabledShellStillAttachesNoAssets() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let module = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/ad-enabled-shell",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let webView = try XCTUnwrap(tab.existingWebView)
        let controller = try XCTUnwrap(webView.configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()

        XCTAssertEqual(module.status, .enabledButEngineUnavailable)
        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertEqual(module.normalTabDecision(for: tab.url).assets, .empty)
        assertNoAdBlockingScriptsOrHandlers(in: webView.configuration.userContentController)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testAuxiliaryConfigurationsAttachNoAdBlockingAssets() {
        let browserConfiguration = BrowserConfiguration()
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .faviconDownload),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .peek),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .miniWindow),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
            browserConfiguration.cacheOptimizedWebViewConfiguration(),
        ]

        for configuration in configurations {
            XCTAssertFalse(configuration.userContentController is UserContentController)
            XCTAssertFalse(
                configuration.userContentController
                    .sumiUsesNormalTabBrowserServicesKitUserContentController
            )
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserScriptsProvider)
            XCTAssertTrue(configuration.userContentController.userScripts.isEmpty)
            assertNoAdBlockingScriptsOrHandlers(in: configuration.userContentController)
        }
    }

    func testTrackingProtectionEnabledAdBlockingDisabledPreservesTrackingRuleAttachment() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let trackingSettings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        trackingSettings.setGlobalMode(.enabled)
        let trackingService = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()])
        )
        let trackingModule = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: { trackingSettings },
            dataStoreFactory: { self.makeTrackingDataStore(defaults: harness.defaults) },
            contentBlockingServiceFactory: { _, _ in trackingService }
        )
        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: trackingModule,
            adBlockingModule: adBlockingModule
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/tracking-enabled-ad-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let controller = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController as? UserContentController
        )
        await controller.awaitContentBlockingAssetsInstalled()
        try await waitForAssets(on: controller) { $0.globalRuleLists.count == 1 }

        XCTAssertFalse(adBlockingModule.isEnabled)
        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 1)
    }

    func testTrackingProtectionDisabledAdBlockingEnabledShellAttachesNoRules() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: adBlockingModule
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/tracking-disabled-ad-enabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let controller = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController as? UserContentController
        )
        await controller.awaitContentBlockingAssetsInstalled()

        XCTAssertFalse(registry.isEnabled(.trackingProtection))
        XCTAssertEqual(adBlockingModule.status, .enabledButEngineUnavailable)
        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertEqual(
            tab.trackingProtectionAppliedAttachmentState,
            SumiTrackingProtectionAttachmentState(siteHost: "example.com", isEnabled: false)
        )
        assertNoAdBlockingScriptsOrHandlers(in: controller)
    }

    func testAdBlockingToggleDoesNotAffectTrackingProtectionSiteOverrides() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let trackingSettings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)
        let url = URL(string: "https://www.example.com/path")!

        trackingSettings.setGlobalMode(.enabled)
        trackingSettings.setSiteOverride(.disabled, for: url)
        adBlockingModule.setEnabled(true)

        XCTAssertTrue(registry.isEnabled(.adBlocking))
        XCTAssertEqual(trackingSettings.globalMode, .enabled)
        XCTAssertEqual(trackingSettings.override(for: url), .disabled)
        XCTAssertFalse(registry.isEnabled(.trackingProtection))

        adBlockingModule.setEnabled(false)

        XCTAssertEqual(trackingSettings.globalMode, .enabled)
        XCTAssertEqual(trackingSettings.override(for: url), .disabled)
    }

    func testTrackingProtectionToggleDoesNotEnableAdBlocking() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )

        registry.enable(.trackingProtection)
        XCTAssertTrue(registry.isEnabled(.trackingProtection))
        XCTAssertFalse(registry.isEnabled(.adBlocking))

        registry.disable(.trackingProtection)
        XCTAssertFalse(registry.isEnabled(.trackingProtection))
        XCTAssertFalse(registry.isEnabled(.adBlocking))
    }

    func testAdBlockingModuleSourceHasNoEngineListCompilerOrTrackingRuntimeIntegration() throws {
        let source = try Self.source(named: "Sumi/ContentBlocking/SumiAdBlockingModule.swift")

        XCTAssertTrue(source.contains("SumiAdBlockingModuleStatus"))
        XCTAssertTrue(source.contains("enabledButEngineUnavailable"))
        XCTAssertTrue(source.contains("moduleRegistry.isEnabled(.adBlocking)"))
        XCTAssertTrue(source.contains("false"))

        for forbiddenPattern in [
            "adblock_rust",
            "adblock-rust",
            "EasyList",
            "EasyPrivacy",
            "SumiContentBlockingService",
            "SumiContentBlockingService.shared",
            "SumiTrackingProtectionModule",
            "SumiTrackingRuleListProvider",
            "SumiTrackingRuleListPipeline",
            "SumiTrackingContentBlockingAssets",
            "SumiTrackingProtectionSettings",
            "SumiTrackingProtectionDataStore",
            "SumiTrackerDataUpdater",
            "SumiWKContentRuleListCompiler",
            "WKContentRuleListStore",
            "compileContentRuleList",
            "WKUserScript",
            "addUserScript",
            "addScriptMessageHandler",
            "URLSession",
            "Timer",
            "scheduledTimer",
            "Task",
            "download",
            "stale",
        ] {
            XCTAssertFalse(source.contains(forbiddenPattern), forbiddenPattern)
        }

        XCTAssertFalse(source.localizedCaseInsensitiveContains("cosmetic"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("scriptlet"))
    }

    func testNormalTabAndAuxiliarySourcesDoNotConsultAdBlockingModule() throws {
        for relativePath in [
            "Sumi/Models/Tab/Tab+WebViewRuntime.swift",
            "Sumi/Models/BrowserConfig/BrowserConfig.swift",
            "Sumi/Favicons/DDG/SumiDDGFaviconUserContentController.swift",
            "Sumi/Managers/PeekManager/PeekWebView.swift",
            "Sumi/Components/MiniWindow/MiniWindowWebView.swift",
            "Sumi/Favicons/DDG/Model/FaviconDownloader.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("adBlockingModule"), relativePath)
            XCTAssertFalse(source.contains("SumiAdBlockingModule"), relativePath)
            XCTAssertFalse(source.contains("SumiAdBlockingAssets"), relativePath)
            XCTAssertFalse(source.contains("SumiAdBlockingNormalTabDecision"), relativePath)
        }
    }

    private func assertNoAdBlockingScriptsOrHandlers(
        in userContentController: WKUserContentController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let wkSources = userContentController.userScripts
            .map(\.source)
            .joined(separator: "\n")
        let providerSources = userContentController.sumiNormalTabUserScriptsProvider?
            .userScripts
            .map(\.source)
            .joined(separator: "\n") ?? ""
        let messageNames = userContentController.sumiNormalTabUserScriptsProvider?
            .userScripts
            .flatMap(\.messageNames)
            .joined(separator: "\n") ?? ""

        for marker in [
            "SumiAdBlocking",
            "sumiAdBlocking",
            "adBlocking",
            "ad-block",
            "adblock",
        ] {
            XCTAssertFalse(wkSources.contains(marker), marker, file: file, line: line)
            XCTAssertFalse(providerSources.contains(marker), marker, file: file, line: line)
            XCTAssertFalse(messageNames.contains(marker), marker, file: file, line: line)
        }
    }

    private func makeTrackingDataStore(defaults: UserDefaults) -> SumiTrackingProtectionDataStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiAdBlockingTrackingData-\(UUID().uuidString)",
                isDirectory: true
            )
        temporaryDirectories.append(directory)
        return SumiTrackingProtectionDataStore(
            userDefaults: defaults,
            storageDirectory: directory
        )
    }

    private static func validRuleListDefinition() -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: "SumiAdBlockingSeparationTrackingRules-\(UUID().uuidString)",
            encodedContentRuleList: """
            [
              {
                "trigger": {
                  "url-filter": ".*tracking-separation-blocked\\\\.example/.*"
                },
                "action": {
                  "type": "block"
                }
              }
            ]
            """
        )
    }

    @discardableResult
    private func waitForAssets(
        on controller: UserContentController,
        where predicate: @escaping (UserContentController.ContentBlockingAssets) -> Bool
    ) async throws -> UserContentController.ContentBlockingAssets {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let assets = controller.contentBlockingAssets, predicate(assets) {
                return assets
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for content-blocking assets")
        return try XCTUnwrap(controller.contentBlockingAssets)
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
