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
        XCTAssertEqual(module.status, .enabledNativeContentBlocking)
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

    func testEnabledNativeContentBlockingReportsCompiledRuleAssetsWithoutScripts() {
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
        XCTAssertEqual(module.status, .enabledNativeContentBlocking)
        XCTAssertEqual(module.assetsIfAvailable().contentRuleListIdentifiers.count, 2)
        XCTAssertEqual(decision.status, .enabledNativeContentBlocking)
        XCTAssertEqual(decision.assets.contentRuleListIdentifiers.count, 2)
        XCTAssertEqual(decision.assets.scriptSources.count, 0)
        XCTAssertEqual(decision.assets.scriptMessageHandlerNames.count, 0)
        XCTAssertNotNil(decision.contentBlockingService)
        XCTAssertTrue(module.hasLoadedRuntime)
    }

    func testDisabledAdblockDoesNotCreateCompilerBoundary() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        var didCreateRuleListStore = false
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            ruleListStoreFactory: { settings, isEnabled in
                didCreateRuleListStore = true
                return AdblockWebKitRuleListStore(settingsStore: settings, isAdblockEnabled: isEnabled)
            }
        )

        XCTAssertEqual(module.normalTabDecision(for: URL(string: "https://example.com")).assets, SumiAdBlockingAssets.empty)
        XCTAssertEqual(module.assetsIfAvailable(), SumiAdBlockingAssets.empty)
        XCTAssertFalse(didCreateRuleListStore)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testSwiftCompilerBoundaryInvokesRustAdapter() async throws {
        let adapter = CountingAdblockRustAdapter(output: .tinyFixture)
        let compiler = AdblockRustCompiler(adapter: adapter)

        let output = try await compiler.compile(
            AdblockCompilationInput(
                sourceIdentifier: "TestAdblock",
                filterTexts: AdblockWebKitRuleListStore.tinyFixtureFilters,
                selectedOutputGroups: [.network, .nativeCosmeticCSS]
            )
        )

        let callCount = await adapter.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(output.convertedNetworkRuleCount, 1)
        XCTAssertEqual(output.convertedNativeCosmeticRuleCount, 3)
        XCTAssertEqual(output.diagnostics.nativeCosmeticRuleCount, 3)
        XCTAssertEqual(output.diagnostics.ignoredScriptletOrProceduralRuleCount, 1)
        XCTAssertFalse(output.diagnostics.isNativeCosmeticGroupEmpty)
        XCTAssertTrue(output.groups.contains { $0.kind == .network })
        XCTAssertTrue(output.groups.contains { $0.kind == .nativeCosmeticCSS })
        XCTAssertNotNil(output.hybridOutput.nativeRuleGroups.network)
        XCTAssertNotNil(output.hybridOutput.nativeRuleGroups.nativeCosmeticCSS)
        XCTAssertEqual(output.hybridOutput.enhancedRuntimeBundle.resources.map(\.kind), [.scriptlet])
        XCTAssertTrue(output.hybridOutput.capabilities.contains(.scriptletResourceCandidate))
    }

    func testTinyFixtureCompilesIntoSeparatedWebKitJSONGroups() async throws {
        let compiler = AdblockRustCompiler()
        let output = try await compiler.compile(
            AdblockCompilationInput(
                sourceIdentifier: "TestAdblock",
                filterTexts: Self.tinyFixtureFiltersWithUnsupportedRule,
                selectedOutputGroups: [.network, .nativeCosmeticCSS]
            )
        )

        XCTAssertEqual(output.inputRuleCount, 5)
        XCTAssertEqual(output.convertedNetworkRuleCount, 1)
        XCTAssertEqual(output.convertedNativeCosmeticRuleCount, 3)
        XCTAssertEqual(output.unsupportedOrIgnoredRuleCount, 1)
        XCTAssertEqual(output.diagnostics.nativeCosmeticRuleCount, 3)
        XCTAssertEqual(output.diagnostics.unsupportedCosmeticRuleCount, 1)
        XCTAssertEqual(output.diagnostics.ignoredScriptletOrProceduralRuleCount, 1)
        XCTAssertFalse(output.diagnostics.isNativeCosmeticGroupEmpty)
        XCTAssertEqual(output.groups.map(\.kind).sorted { $0.rawValue < $1.rawValue }, [.nativeCosmeticCSS, .network])
        XCTAssertEqual(output.diagnostics.unsupportedRules.count, 1)
        XCTAssertTrue(output.diagnostics.unsupportedRules[0].reason.localizedCaseInsensitiveContains("script"))
        XCTAssertFalse(output.contentHash.isEmpty)

        let networkGroup = try XCTUnwrap(output.groups.first { $0.kind == .network })
        let cosmeticGroup = try XCTUnwrap(output.groups.first { $0.kind == .nativeCosmeticCSS })
        let networkRules = try Self.decodedRuleList(networkGroup.encodedContentRuleList)
        let cosmeticRules = try Self.decodedRuleList(cosmeticGroup.encodedContentRuleList)

        let networkActionTypes = networkRules.compactMap { ($0["action"] as? [String: Any])?["type"] as? String }
        XCTAssertEqual(networkActionTypes.filter { $0 == "block" }.count, 1)
        XCTAssertTrue(networkActionTypes.contains("ignore-previous-rules"))
        XCTAssertEqual(cosmeticRules.count, 3)
        XCTAssertTrue(cosmeticRules.allSatisfy {
            ($0["action"] as? [String: Any])?["type"] as? String == "css-display-none"
        })
        let cosmeticSelectors = cosmeticRules.compactMap {
            ($0["action"] as? [String: Any])?["selector"] as? String
        }
        XCTAssertTrue(cosmeticSelectors.contains(".ad-banner"))
        XCTAssertTrue(cosmeticSelectors.contains(".sponsored"))
        XCTAssertTrue(cosmeticSelectors.contains("#sponsor.card[data-ad=\"1\"]"))
        XCTAssertTrue(cosmeticRules.contains { rule in
            ((rule["trigger"] as? [String: Any])?["if-domain"] as? [String]) == ["example.test"]
                && ((rule["action"] as? [String: Any])?["selector"] as? String) == ".sponsored"
        })
    }

    func testHybridCompilerClassifiesRedirectAndProceduralCandidatesWithoutNativeParserBypass() async throws {
        let adapter = CountingAdblockRustAdapter(
            output: AdblockRustAdapterOutput(
                network: [],
                nativeCosmeticCSS: [],
                unsupportedOrIgnored: [
                    AdblockRustAdapterDiagnostic(
                        rule: "||cdn.example/script.js$redirect=noopjs",
                        reason: "unsupported by WebKit content-blocking conversion"
                    ),
                    AdblockRustAdapterDiagnostic(
                        rule: "example.com#?#.ad:has-text(Sponsored)",
                        reason: "unsupported procedural cosmetic rule"
                    ),
                ]
            )
        )
        let compiler = AdblockRustCompiler(adapter: adapter)

        let output = try await compiler.compile(
            AdblockCompilationInput(
                sourceIdentifier: "Hybrid",
                filterTexts: [
                    "||cdn.example/script.js$redirect=noopjs",
                    "example.com#?#.ad:has-text(Sponsored)",
                ],
                selectedOutputGroups: [.network, .nativeCosmeticCSS]
            )
        )

        XCTAssertTrue(output.hybridOutput.nativeRuleGroups.network?.convertedRuleCount ?? 0 == 0)
        XCTAssertEqual(
            output.hybridOutput.enhancedRuntimeBundle.resources.map(\.kind).sorted { $0.rawValue < $1.rawValue },
            [.noopRedirect, .cosmeticCleanup]
                .sorted { $0.rawValue < $1.rawValue }
        )
        XCTAssertTrue(output.hybridOutput.capabilities.contains(.redirectResourceCandidate))
        XCTAssertTrue(output.hybridOutput.capabilities.contains(.enhancedCosmeticCleanup))
        XCTAssertEqual(output.hybridOutput.enhancedRuntimeBundle.unsupportedDiagnostics.count, 2)
    }

    func testCompilerRejectsUnexpectedNativeCosmeticActionsFromAdapter() async throws {
        let adapter = CountingAdblockRustAdapter(
            output: AdblockRustAdapterOutput(
                network: [],
                nativeCosmeticCSS: [
                    AdblockRustContentRule(
                        action: .object(["type": .string("script"), "source": .string("alert(1)")]),
                        trigger: .object(["url-filter": .string(".*")])
                    ),
                ],
                unsupportedOrIgnored: []
            )
        )
        let compiler = AdblockRustCompiler(adapter: adapter)

        do {
            _ = try await compiler.compile(
                AdblockCompilationInput(
                    sourceIdentifier: "TestAdblock",
                    filterTexts: ["##+js(sumi-future-scriptlet)"],
                    selectedOutputGroups: [.nativeCosmeticCSS]
                )
            )
            XCTFail("Expected invalid adapter output")
        } catch AdblockRustCompilerError.invalidAdapterOutput(let message) {
            XCTAssertTrue(message.contains("nativeCosmeticCSS"))
        }
    }

    func testCompilerOutputHashesAreStableForIdenticalInput() async throws {
        let compiler = AdblockRustCompiler()
        let input = AdblockCompilationInput(
            sourceIdentifier: "TestAdblock",
            filterTexts: Self.tinyFixtureFiltersWithUnsupportedRule,
            selectedOutputGroups: [.network, .nativeCosmeticCSS]
        )

        let first = try await compiler.compile(input)
        let second = try await compiler.compile(input)

        XCTAssertEqual(first.contentHash, second.contentHash)
        XCTAssertEqual(first.groups.map(\.contentHash), second.groups.map(\.contentHash))
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

        XCTAssertEqual(module.status, .enabledNativeContentBlocking)
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
        XCTAssertEqual(adBlockingModule.status, .enabledNativeContentBlocking)
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

    func testAdblockSettingsPersistCosmeticModeAutoUpdateAndSelectedLists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)

        XCTAssertTrue(settings.autoUpdateEnabled)
        XCTAssertEqual(settings.cosmeticMode, .nativeCSS)
        XCTAssertTrue(settings.regionalListSelection.identifiers.isEmpty)
        XCTAssertTrue(settings.selectedLists.usesDefaultSelection)
        XCTAssertFalse(settings.listSelectionRequiresUpdate)

        settings.autoUpdateEnabled = false
        settings.cosmeticMode = .enhancedRuntime
        settings.regionalListSelection = SumiAdblockRegionalListSelection(identifiers: ["de", "pl"])
        settings.selectedLists = SumiAdblockFilterListSelection(identifiers: ["easylist", "ru-adlist"])

        let reloaded = AdblockSettingsStore(userDefaults: harness.defaults)
        XCTAssertFalse(reloaded.autoUpdateEnabled)
        XCTAssertEqual(reloaded.cosmeticMode, .enhancedRuntime)
        XCTAssertEqual(reloaded.regionalListSelection.identifiers, ["de", "pl"])
        XCTAssertEqual(reloaded.selectedLists.identifiers, ["easylist", "ru-adlist"])
        XCTAssertTrue(reloaded.listSelectionRequiresUpdate)
    }

    func testDisabledAdblockCanPersistListSelectionWithoutCreatingRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.selectedLists = SumiAdblockFilterListSelection(identifiers: ["easylist", "ru-adlist"])
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings }
        )

        XCTAssertFalse(module.isEnabled)
        XCTAssertEqual(module.assetsIfAvailable(), .empty)
        XCTAssertEqual(module.normalTabDecision(for: URL(string: "https://example.com")).assets, .empty)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertEqual(AdblockSettingsStore(userDefaults: harness.defaults).selectedLists.identifiers, ["easylist", "ru-adlist"])
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
        XCTAssertEqual(module.assetsIfAvailable().contentRuleListIdentifiers.count, 2)
        XCTAssertEqual(module.normalTabDecision(for: nil).assets.scriptSources, [])
        XCTAssertEqual(module.normalTabDecision(for: nil).assets.scriptMessageHandlerNames, [])
    }

    func testEnhancedRuntimeInstallsOnlyAfterAllNormalTabGatesPass() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.cosmeticMode = .enhancedRuntime
        let manifestStore = AdblockUpdateManifestStore(
            rootDirectory: temporaryAdblockDirectory()
        )
        try await seedActiveManifest(in: manifestStore)
        var capturedStore: AdblockWebKitRuleListStore?
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            ruleListStoreFactory: { settings, isEnabled in
                let store = AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler()
                )
                capturedStore = store
                return store
            }
        )

        _ = module.normalTabDecision(for: URL(string: "https://example.com"))
        await capturedStore?.loadActiveManifestIfEnabled()

        let scripts = module.normalTabEnhancedRuntimeScripts(for: URL(string: "https://example.com"))
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].source.contains("SUMI_ADBLOCK_ENHANCED_RUNTIME"))
        XCTAssertTrue(scripts[0].source.contains("sumi.adblock.enhanced"))
        XCTAssertTrue(scripts[0].messageNames.isEmpty)
    }

    func testEnhancedRuntimeFirstSliceIsLocalBoundedAndHasNoEvalObserverTimerOrBridge() throws {
        let source = try Self.source(named: "Sumi/ContentBlocking/SumiAdblockEnhancedRuntime.swift")

        XCTAssertTrue(source.contains("SUMI_ADBLOCK_ENHANCED_RUNTIME"))
        XCTAssertTrue(source.contains("sumi.adblock.enhanced"))
        XCTAssertTrue(source.contains("maxElements = 50"))
        XCTAssertTrue(source.contains("data-sumi-adblock-enhanced-cleanup"))
        for forbidden in [
            "eval(",
            "new Function",
            "MutationObserver",
            "setInterval",
            "setTimeout",
            "addScriptMessageHandler",
            "WKWebExtension",
            "URLSession",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    func testNativeCSSAndDisabledModesRemainAdblockRuntimeScriptFreeInTabProvider() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/native-css-free",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        settings.cosmeticMode = .nativeCSS
        XCTAssertFalse(
            tab.normalTabUserScriptsProvider(for: tab.url)
                .userScripts
                .map(\.source)
                .joined(separator: "\n")
                .contains("SUMI_ADBLOCK_ENHANCED_RUNTIME")
        )

        settings.cosmeticMode = .off
        XCTAssertFalse(
            tab.normalTabUserScriptsProvider(for: tab.url)
                .userScripts
                .map(\.source)
                .joined(separator: "\n")
                .contains("SUMI_ADBLOCK_ENHANCED_RUNTIME")
        )

        module.setEnabled(false)
        XCTAssertFalse(
            tab.normalTabUserScriptsProvider(for: tab.url)
                .userScripts
                .map(\.source)
                .joined(separator: "\n")
                .contains("SUMI_ADBLOCK_ENHANCED_RUNTIME")
        )
    }

    func testEnhancedRuntimeGatesKeepDisabledNativeCSSOffAndPerSiteDisabledScriptFree() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let manifestStore = AdblockUpdateManifestStore(
            rootDirectory: temporaryAdblockDirectory()
        )
        try await seedActiveManifest(in: manifestStore)
        var capturedStore: AdblockWebKitRuleListStore?
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            sitePolicyFactory: { sitePolicyStore },
            ruleListStoreFactory: { settings, isEnabled in
                let store = AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler()
                )
                capturedStore = store
                return store
            }
        )
        let url = URL(string: "https://example.com")!
        _ = module.normalTabDecision(for: url)
        await capturedStore?.loadActiveManifestIfEnabled()

        settings.cosmeticMode = .off
        XCTAssertTrue(module.normalTabEnhancedRuntimeScripts(for: url).isEmpty)

        settings.cosmeticMode = .nativeCSS
        XCTAssertTrue(module.normalTabEnhancedRuntimeScripts(for: url).isEmpty)

        settings.cosmeticMode = .enhancedRuntime
        sitePolicyStore.setSiteOverride(.disabled, for: url)
        XCTAssertTrue(module.normalTabEnhancedRuntimeScripts(for: url).isEmpty)

        module.setEnabled(false)
        sitePolicyStore.setSiteOverride(.allowed, for: url)
        XCTAssertTrue(module.normalTabEnhancedRuntimeScripts(for: url).isEmpty)
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

        XCTAssertEqual(decision.status, .enabledNativeContentBlocking)
        XCTAssertEqual(decision.assets, .empty)
        XCTAssertNil(decision.contentBlockingService)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testPerSitePolicyNormalizesHostWithoutPathOrQuery() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)

        sitePolicyStore.setSiteOverride(
            .disabled,
            for: URL(string: "https://www.example.com/path/to/page?ad=1#fragment")
        )

        XCTAssertEqual(sitePolicyStore.sortedSiteOverrides.map(\.host), ["example.com"])
        XCTAssertEqual(
            sitePolicyStore.effectivePolicy(
                for: URL(string: "https://example.com/other"),
                globalEnabled: true
            ),
            SumiAdblockEffectivePolicy(host: "example.com", isEnabled: false)
        )
    }

    func testSettingsOverrideChangesAreReflectedByModuleEffectivePolicy() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore }
        )
        let url = URL(string: "https://www.example.com/path")!

        XCTAssertTrue(module.effectivePolicy(for: url).isEnabled)

        sitePolicyStore.setSiteOverride(.disabled, for: url)
        XCTAssertFalse(module.effectivePolicy(for: url).isEnabled)

        sitePolicyStore.removeSiteOverride(forNormalizedHost: "example.com")
        XCTAssertTrue(module.effectivePolicy(for: url).isEnabled)
    }

    func testAdblockSitePolicyDoesNotModifyTrackingProtectionPolicy() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let trackingSettings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        let adblockSitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let url = URL(string: "https://www.example.com/path")!

        trackingSettings.setGlobalMode(.enabled)
        trackingSettings.setSiteOverride(.enabled, for: url)
        adblockSitePolicyStore.setSiteOverride(.disabled, for: url)

        XCTAssertEqual(trackingSettings.override(for: url), .enabled)
        XCTAssertEqual(adblockSitePolicyStore.override(for: url), .disabled)
    }

    func testTrackingProtectionSitePolicyDoesNotModifyAdblockPolicy() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let trackingSettings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        let adblockSitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let url = URL(string: "https://www.example.com/path")!

        adblockSitePolicyStore.setSiteOverride(.disabled, for: url)
        trackingSettings.setSiteOverride(.disabled, for: url)

        XCTAssertEqual(adblockSitePolicyStore.override(for: url), .disabled)
        XCTAssertEqual(trackingSettings.override(for: url), .disabled)
    }

    func testGlobalDisabledIgnoresPerSiteAllowedWithoutCreatingRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        sitePolicyStore.setSiteOverride(.allowed, for: URL(string: "https://www.example.com"))
        var didCreateRuleListStore = false
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore },
            ruleListStoreFactory: { settings, isEnabled in
                didCreateRuleListStore = true
                return AdblockWebKitRuleListStore(settingsStore: settings, isAdblockEnabled: isEnabled)
            }
        )

        let decision = module.normalTabDecision(for: URL(string: "https://example.com"))

        XCTAssertEqual(decision.status, .disabled)
        XCTAssertFalse(decision.effectivePolicy.isEnabled)
        XCTAssertNil(decision.contentBlockingService)
        XCTAssertFalse(didCreateRuleListStore)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testPerSiteDisabledPolicyPreventsRuleListAttachmentOnNormalTab() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        sitePolicyStore.setSiteOverride(.disabled, for: URL(string: "https://www.example.com/path"))
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/reload",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let controller = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertEqual(tab.adblockAppliedAttachmentState, SumiAdblockAttachmentState(siteHost: "example.com", isEnabled: false))
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testPerSiteReEnabledPolicyAllowsRuleListAttachmentAfterManualReload() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let url = URL(string: "https://www.example.com/path")!
        sitePolicyStore.setSiteOverride(.disabled, for: url)
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: url.absoluteString,
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.setupWebView()
        let originalWebView = try XCTUnwrap(tab.existingWebView)
        let originalController = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await originalController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(originalController.contentBlockingAssetSummary.globalRuleListCount, 0)

        sitePolicyStore.setSiteOverride(.allowed, for: url)
        tab.markAdblockReloadRequiredIfNeeded(afterChangingOverrideFor: url)

        XCTAssertTrue(tab.isAdblockReloadRequired)
        XCTAssertTrue(tab.existingWebView === originalWebView)

        XCTAssertTrue(
            tab.rebuildNormalWebViewForAdblockIfNeeded(
                targetURL: tab.url,
                reason: "SumiAdBlockingModuleTests.manualReload"
            )
        )
        let rebuiltController = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController.sumiNormalTabUserContentController
        )
        try await waitForAssets(on: rebuiltController) { $0.globalRuleListCount == 2 }
        tab.clearAdblockReloadRequirementIfResolved(for: tab.url)
        XCTAssertFalse(tab.isAdblockReloadRequired)
    }

    func testChangingAdblockPolicyMarksReloadRequiredWithoutAutoReload() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/no-auto-reload",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.setupWebView()
        let originalWebView = try XCTUnwrap(tab.existingWebView)
        let controller = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        try await waitForAssets(on: controller) { $0.globalRuleListCount == 2 }

        sitePolicyStore.setSiteOverride(.disabled, for: tab.url)
        tab.markAdblockReloadRequiredIfNeeded(afterChangingOverrideFor: tab.url)

        XCTAssertTrue(tab.isAdblockReloadRequired)
        XCTAssertTrue(tab.existingWebView === originalWebView)
        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 2)
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
        let compilerSource = try Self.source(named: "Sumi/ContentBlocking/SumiAdblockRustCompiler.swift")

        XCTAssertTrue(source.contains("SumiAdBlockingModuleStatus"))
        XCTAssertTrue(source.contains("enabledNativeContentBlocking"))
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
        ] {
            XCTAssertFalse(source.contains(forbiddenPattern), forbiddenPattern)
        }

        XCTAssertTrue(compilerSource.contains("AdblockRustHelperExecutableAdapter"))
        XCTAssertTrue(compilerSource.contains("SUMI_ADBLOCK_RUST_ADAPTER"))
        XCTAssertFalse(compilerSource.contains("networkContentRule(from:"))
        XCTAssertFalse(compilerSource.contains("cosmeticContentRule(from:"))
        XCTAssertFalse(compilerSource.contains("escapedLooseURLFilter"))
    }

    func testAdblockRustUsageIsIsolatedToCompilerBoundaryAndVendorAdapter() throws {
        let allowedPaths: Set<String> = [
            "Sumi/ContentBlocking/SumiAdblockRustCompiler.swift",
            "Vendor/Brave/README.md",
            "Vendor/Brave/AdblockRustAdapter/Cargo.toml",
            "Vendor/Brave/AdblockRustAdapter/Cargo.lock",
            "Vendor/Brave/AdblockRustAdapter/src/main.rs",
            "LICENSE_NOTES.md",
        ]
        let output = try Self.runSourceSearch(
            pattern: "adblock-rust|adblock::|sumi-adblock-rust-adapter|SUMI_ADBLOCK_RUST_ADAPTER"
        )
        let unexpected = output
            .split(separator: "\n")
            .map(String.init)
            .compactMap { line -> String? in
                guard let path = line.split(separator: ":", maxSplits: 1).first.map(String.init),
                      !allowedPaths.contains(path),
                      !path.hasPrefix("SumiTests/")
                else { return nil }
                return line
            }

        XCTAssertTrue(unexpected.isEmpty, unexpected.joined(separator: "\n"))
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

    private func temporaryAdblockDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiAdBlockingHybrid-\(UUID().uuidString)",
                isDirectory: true
            )
        temporaryDirectories.append(directory)
        return directory
    }

    private func seedActiveManifest(in store: AdblockUpdateManifestStore) async throws {
        let manifest = AdblockCompiledGenerationManifest(
            schemaVersion: 1,
            activeGenerationId: "hybrid-test-generation",
            createdDate: Date(),
            selectedFilterLists: [],
            webKitRuleListIdentifiers: [
                "sumi.adblock.network.hybridtest",
                "sumi.adblock.nativeCSS.hybridtest",
            ],
            groupedOutputs: [
                AdblockCompiledGenerationManifest.Group(
                    kind: .network,
                    webKitIdentifier: "sumi.adblock.network.hybridtest",
                    contentHash: "network",
                    convertedRuleCount: 1
                ),
                AdblockCompiledGenerationManifest.Group(
                    kind: .nativeCosmeticCSS,
                    webKitIdentifier: "sumi.adblock.nativeCSS.hybridtest",
                    contentHash: "css",
                    convertedRuleCount: 1
                ),
            ],
            compilerDiagnosticsSummary: "hybrid test",
            lastSuccessfulUpdateDate: Date(),
            previousGenerationId: nil
        )
        try await store.commit(
            manifest: manifest,
            httpMetadata: [:],
            stagedRawListURLs: [:],
            stagedCompiledGroupURLs: [:]
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
        let sourceURL = repoRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func runSourceSearch(pattern: String) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["rg", "-n", "--glob", "!Vendor/Brave/AdblockRustAdapter/target/**", pattern]
        process.currentDirectoryURL = repoRoot()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodedRuleList(_ encoded: String) throws -> [[String: Any]] {
        let data = Data(encoded.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private static let tinyFixtureFiltersWithUnsupportedRule =
        AdblockWebKitRuleListStore.tinyFixtureFilters + ["example.com##+js(sumi-future-scriptlet)"]
}

private actor CountingAdblockRustAdapter: AdblockRustAdapterInvoking {
    private(set) var callCount = 0
    private let output: AdblockRustAdapterOutput

    init(output: AdblockRustAdapterOutput) {
        self.output = output
    }

    func compile(_ normalizedRules: [String]) async throws -> AdblockRustAdapterOutput {
        callCount += 1
        return output
    }
}

private extension AdblockRustAdapterOutput {
    static let tinyFixture = AdblockRustAdapterOutput(
        network: [
            AdblockRustContentRule(
                action: .object(["type": .string("block")]),
                trigger: .object(["url-filter": .string("^[^:]+:(//)?([^/]+\\\\.)?ads\\\\.example\\\\.test")])
            ),
        ],
        nativeCosmeticCSS: [
            AdblockRustContentRule(
                action: .object([
                    "type": .string("css-display-none"),
                    "selector": .string(".ad-banner"),
                ]),
                trigger: .object(["url-filter": .string(".*")])
            ),
            AdblockRustContentRule(
                action: .object([
                    "type": .string("css-display-none"),
                    "selector": .string(".sponsored"),
                ]),
                trigger: .object([
                    "url-filter": .string(".*"),
                    "if-domain": .array([.string("example.test")]),
                ])
            ),
            AdblockRustContentRule(
                action: .object([
                    "type": .string("css-display-none"),
                    "selector": .string("#sponsor.card[data-ad=\"1\"]"),
                ]),
                trigger: .object([
                    "url-filter": .string(".*"),
                    "if-domain": .array([.string("example.test")]),
                ])
            ),
        ],
        unsupportedOrIgnored: [
            AdblockRustAdapterDiagnostic(
                rule: "example.com##+js(sumi-future-scriptlet)",
                reason: "unsupported by adblock-rust content-blocking conversion: ScriptletInjectionsNotSupported"
            ),
        ]
    )
}
