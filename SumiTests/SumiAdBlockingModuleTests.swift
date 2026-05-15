import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAdBlockingModuleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
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
        XCTAssertEqual(module.status, .enabledNativeSkeleton)
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

    func testEnabledNativeSkeletonReportsNativeRuleAssetsWithoutScripts() {
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
        XCTAssertEqual(module.status, .enabledNativeSkeleton)
        XCTAssertEqual(module.assetsIfAvailable().contentRuleListIdentifiers.count, 2)
        XCTAssertEqual(decision.status, .enabledNativeSkeleton)
        XCTAssertEqual(decision.assets.contentRuleListIdentifiers.count, 2)
        XCTAssertEqual(decision.assets.scriptSources.count, 0)
        XCTAssertEqual(decision.assets.scriptMessageHandlerNames.count, 0)
        XCTAssertNotNil(decision.contentBlockingService)
        XCTAssertTrue(module.hasLoadedRuntime)
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

        let togglesSource = try Self.source(named: "Sumi/Components/Settings/SumiSettingsModuleToggles.swift")

        XCTAssertFalse(togglesSource.contains("normalTabDecision("))
        XCTAssertFalse(togglesSource.contains("ruleListStoreIfEnabled("))
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
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertEqual(module.normalTabDecision(for: tab.url).assets, .empty)
        assertNoAdBlockingScriptsOrHandlers(in: webView.configuration.userContentController)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testNormalTabCreationWithAdBlockingEnabledAttachesNativeRuleListsOnly() async throws {
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
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(module.status, .enabledNativeSkeleton)
        try await waitForAssets(on: controller) { $0.globalRuleListCount == 2 }
        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 2)
        XCTAssertEqual(module.normalTabDecision(for: tab.url).assets.scriptSources.count, 0)
        assertNoAdBlockingScriptsOrHandlers(in: webView.configuration.userContentController)
        XCTAssertTrue(module.hasLoadedRuntime)
    }

    func testAuxiliaryConfigurationsAttachNoAdBlockingAssets() {
        let browserConfiguration = BrowserConfiguration()
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .faviconDownload),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .miniWindow),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
        ]

        for configuration in configurations {
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserContentController)
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
            tab.existingWebView?.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()
        try await waitForAssets(on: controller) { $0.globalRuleListCount == 1 }

        XCTAssertFalse(adBlockingModule.isEnabled)
        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 1)
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
            tab.existingWebView?.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()

        XCTAssertFalse(registry.isEnabled(.trackingProtection))
        XCTAssertEqual(adBlockingModule.status, .enabledNativeSkeleton)
        try await waitForAssets(on: controller) { $0.globalRuleListCount == 2 }
        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 2)
        XCTAssertEqual(
            tab.trackingProtectionAppliedAttachmentState,
            SumiTrackingProtectionAttachmentState(siteHost: "example.com", isEnabled: false)
        )
        assertNoAdBlockingScriptsOrHandlers(in: controller.wkUserContentController)
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

    func testAdblockSettingsPersistCosmeticModeAutoUpdateAndRegionalPlaceholders() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)

        XCTAssertTrue(settings.autoUpdateEnabled)
        XCTAssertEqual(settings.cosmeticMode, .nativeCSS)
        XCTAssertTrue(settings.regionalListSelection.identifiers.isEmpty)

        settings.autoUpdateEnabled = false
        settings.cosmeticMode = .enhancedRuntime
        settings.regionalListSelection = SumiAdblockRegionalListSelection(identifiers: ["de", "pl"])

        let reloaded = AdblockSettingsStore(userDefaults: harness.defaults)
        XCTAssertFalse(reloaded.autoUpdateEnabled)
        XCTAssertEqual(reloaded.cosmeticMode, .enhancedRuntime)
        XCTAssertEqual(reloaded.regionalListSelection.identifiers, ["de", "pl"])
    }

    func testCosmeticModesOnlySelectNativeRuleListsAndNeverScripts() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)

        settings.cosmeticMode = .off
        var module = SumiAdBlockingModule(moduleRegistry: registry, settingsFactory: { settings })
        XCTAssertEqual(module.assetsIfAvailable().contentRuleListIdentifiers.count, 1)
        XCTAssertEqual(module.normalTabDecision(for: nil).assets.scriptSources, [])

        settings.cosmeticMode = .nativeCSS
        module = SumiAdBlockingModule(moduleRegistry: registry, settingsFactory: { settings })
        XCTAssertEqual(module.assetsIfAvailable().contentRuleListIdentifiers.count, 2)
        XCTAssertEqual(module.normalTabDecision(for: nil).assets.scriptSources, [])

        settings.cosmeticMode = .enhancedRuntime
        module = SumiAdBlockingModule(moduleRegistry: registry, settingsFactory: { settings })
        XCTAssertEqual(module.assetsIfAvailable().contentRuleListIdentifiers.count, 1)
        XCTAssertEqual(module.normalTabDecision(for: nil).assets.scriptSources, [])
        XCTAssertEqual(module.normalTabDecision(for: nil).assets.scriptMessageHandlerNames, [])
    }

    func testCosmeticModeChangeUpdatesEnabledNativeRuleListPolicy() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.cosmeticMode = .nativeCSS
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings }
        )
        let decision = module.normalTabDecision(for: URL(string: "https://example.com"))
        let service = try XCTUnwrap(decision.contentBlockingService)
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingServices: [service]
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        try await waitForAssets(on: normalTabController) { $0.globalRuleListCount == 2 }

        settings.cosmeticMode = .off

        let summary = try await waitForAssets(on: normalTabController) { $0.globalRuleListCount == 1 }
        XCTAssertEqual(summary.updateRuleCount, 1)
    }

    func testPerSiteDisabledPolicyPreventsRuleListAttachment() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        sitePolicyStore.setSiteOverride(.disabled, for: URL(string: "https://www.example.com/page"))
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore }
        )

        let decision = module.normalTabDecision(for: URL(string: "https://example.com/other"))

        XCTAssertEqual(decision.status, .enabledNativeSkeleton)
        XCTAssertEqual(decision.assets, .empty)
        XCTAssertNil(decision.contentBlockingService)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testDisablingAdblockRemovesRuleListsFromExistingController() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let module = SumiAdBlockingModule(moduleRegistry: registry)
        let service = try XCTUnwrap(
            module.normalTabDecision(for: URL(string: "https://example.com")).contentBlockingService
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingServices: [service]
        )
        let normalController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        try await waitForAssets(on: normalController) { $0.globalRuleListCount == 2 }

        module.setEnabled(false)
        try await waitForAssets(on: normalController) { $0.globalRuleListCount == 0 }

        XCTAssertFalse(module.isEnabled)
        XCTAssertEqual(normalController.contentBlockingAssetSummary.globalRuleListCount, 0)
    }

    func testAdBlockingModuleSourceHasNoRustWebExtensionUpdaterOrRuntimeScriptIntegration() throws {
        let source = try Self.source(named: "Sumi/ContentBlocking/SumiAdBlockingModule.swift")

        XCTAssertTrue(source.contains("SumiAdBlockingModuleStatus"))
        XCTAssertTrue(source.contains("enabledNativeSkeleton"))
        XCTAssertTrue(source.contains("moduleRegistry.isEnabled(.adBlocking)"))

        for forbiddenPattern in [
            "adblock_rust",
            "adblock-rust",
            "EasyList",
            "EasyPrivacy",
            "SumiContentBlockingService.shared",
            "SumiTrackingProtectionModule",
            "SumiTrackingRuleListProvider",
            "SumiTrackingRuleListPipeline",
            "SumiTrackingContentBlockingAssets",
            "SumiTrackingProtectionSettings",
            "SumiTrackingProtectionDataStore",
            "SumiTrackerDataUpdater",
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

        XCTAssertFalse(source.localizedCaseInsensitiveContains("scriptlet"))
    }

    func testAuxiliarySourcesDoNotConsultAdBlockingModule() throws {
        for relativePath in [
            "Sumi/UserScripts/SumiNormalTabUserScripts.swift",
            "Sumi/Managers/GlanceManager/GlanceWebView.swift",
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
        on controller: SumiNormalTabUserContentControlling,
        where predicate: @escaping (SumiNormalTabContentBlockingAssetSummary) -> Bool
    ) async throws -> SumiNormalTabContentBlockingAssetSummary {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let summary = controller.contentBlockingAssetSummary
            if summary.isInstalled, predicate(summary) {
                return summary
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for content-blocking assets")
        return controller.contentBlockingAssetSummary
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
