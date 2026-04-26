import BrowserServicesKit
import TrackerRadarKit
import UserScript
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserConfigurationNormalTabTests: XCTestCase {
    func testNormalTabConfigurationUsesBSKControllerAndProfileStore() async throws {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")
        )

        XCTAssertTrue(
            configuration.userContentController
                .sumiUsesNormalTabBrowserServicesKitUserContentController
        )
        XCTAssertNotNil(configuration.userContentController.sumiNormalTabUserScriptsProvider)
        XCTAssertTrue(configuration.userContentController is UserContentController)
        XCTAssertTrue(configuration.processPool === browserConfiguration.normalTabProcessPool)
        XCTAssertTrue(configuration.websiteDataStore === profile.dataStore)

        let controller = try XCTUnwrap(configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()
        XCTAssertFalse(configuration.userContentController.userScripts.isEmpty)
        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
    }

    func testBrowserManagerStartupWithTrackingDisabledDoesNotInitializeTrackingRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabTrackingRuntimeProbe()
        let module = makeProbeTrackingModule(
            registry: registry,
            probe: probe,
            defaults: harness.defaults
        )

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: module
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertFalse(registry.isEnabled(.trackingProtection))
        XCTAssertEqual(probe.settingsCount, 0)
        XCTAssertEqual(probe.dataStoreCount, 0)
        XCTAssertEqual(probe.serviceCount, 0)
    }

    func testTabNormalWebViewCreationWithTrackingDisabledDoesNotInitializeTrackingRuntime() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabTrackingRuntimeProbe()
        let module = makeProbeTrackingModule(
            registry: registry,
            probe: probe,
            defaults: harness.defaults
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/tracking-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let webView = try XCTUnwrap(tab.existingWebView)
        let controller = try XCTUnwrap(webView.configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertEqual(probe.settingsCount, 0)
        XCTAssertEqual(probe.dataStoreCount, 0)
        XCTAssertEqual(probe.serviceCount, 0)
    }

    func testEnabledTrackingModuleAttachesRulesAndDisableBlocksFutureNormalTabs() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        SumiTrackingProtectionSettings(userDefaults: harness.defaults).setGlobalMode(.enabled)
        let probe = NormalTabTrackingRuntimeProbe()
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()])
        )
        let module = makeProbeTrackingModule(
            registry: registry,
            probe: probe,
            defaults: harness.defaults,
            service: service
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: module
        )

        let enabledTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/tracking-enabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        enabledTab.setupWebView()
        let enabledController = try XCTUnwrap(
            enabledTab.existingWebView?.configuration.userContentController as? UserContentController
        )
        await enabledController.awaitContentBlockingAssetsInstalled()
        try await waitForAssets(on: enabledController) { $0.globalRuleLists.count == 1 }

        XCTAssertEqual(probe.settingsCount, 1)
        XCTAssertEqual(probe.dataStoreCount, 1)
        XCTAssertEqual(probe.serviceCount, 1)

        registry.disable(.trackingProtection)
        let disabledTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/tracking-disabled-after-toggle",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        disabledTab.setupWebView()
        let disabledController = try XCTUnwrap(
            disabledTab.existingWebView?.configuration.userContentController as? UserContentController
        )
        await disabledController.awaitContentBlockingAssetsInstalled()

        XCTAssertEqual(disabledController.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertEqual(probe.serviceCount, 1)
    }

    func testEnabledTrackingModuleWithSiteDisabledAttachesNoRulesAndNoService() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        settings.setGlobalMode(.enabled)
        settings.setSiteOverride(.disabled, for: URL(string: "https://www.example.com/path")!)
        let probe = NormalTabTrackingRuntimeProbe()
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()])
        )
        let module = makeProbeTrackingModule(
            registry: registry,
            probe: probe,
            defaults: harness.defaults,
            service: service
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: module
        )

        let tab = browserManager.tabManager.createNewTab(
            url: "https://sub.example.com/site-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.setupWebView()
        let controller = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController as? UserContentController
        )
        await controller.awaitContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertEqual(probe.settingsCount, 1)
        XCTAssertEqual(probe.dataStoreCount, 0)
        XCTAssertEqual(probe.serviceCount, 0)
        XCTAssertEqual(
            tab.trackingProtectionAppliedAttachmentState,
            SumiTrackingProtectionAttachmentState(siteHost: "example.com", isEnabled: false)
        )
    }

    func testSiteOverrideChangeMarksReloadRequiredAndManualRebuildAppliesPolicy() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        settings.setGlobalMode(.enabled)
        let probe = NormalTabTrackingRuntimeProbe()
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()])
        )
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                probe.settingsCount += 1
                return settings
            },
            dataStoreFactory: {
                probe.dataStoreCount += 1
                return SumiTrackingProtectionDataStore(
                    userDefaults: harness.defaults,
                    storageDirectory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("SumiNormalTabReloadRequired-\(UUID().uuidString)", isDirectory: true)
                )
            },
            contentBlockingServiceFactory: { _, _ in
                probe.serviceCount += 1
                return service
            }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/reload-required",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.setupWebView()
        let originalWebView = try XCTUnwrap(tab.existingWebView)
        let originalController = try XCTUnwrap(
            originalWebView.configuration.userContentController as? UserContentController
        )
        await originalController.awaitContentBlockingAssetsInstalled()
        try await waitForAssets(on: originalController) { $0.globalRuleLists.count == 1 }

        settings.setSiteOverride(.disabled, for: tab.url)
        tab.markTrackingProtectionReloadRequiredIfNeeded(afterChangingOverrideFor: tab.url)

        XCTAssertTrue(tab.isTrackingProtectionReloadRequired)
        XCTAssertTrue(tab.existingWebView === originalWebView)

        XCTAssertTrue(
            tab.rebuildNormalWebViewForTrackingProtectionIfNeeded(
                targetURL: tab.url,
                reason: "BrowserConfigurationNormalTabTests.manualReload"
            )
        )
        let rebuiltWebView = try XCTUnwrap(tab.existingWebView)
        XCTAssertFalse(rebuiltWebView === originalWebView)
        let rebuiltController = try XCTUnwrap(
            rebuiltWebView.configuration.userContentController as? UserContentController
        )
        await rebuiltController.awaitContentBlockingAssetsInstalled()
        XCTAssertEqual(rebuiltController.contentBlockingAssets?.globalRuleLists.count, 0)

        tab.clearTrackingProtectionReloadRequirementIfResolved(for: tab.url)
        XCTAssertFalse(tab.isTrackingProtectionReloadRequired)
    }

    func testChangingOverrideForNonCurrentSiteDoesNotMarkReloadRequired() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        settings.setGlobalMode(.enabled)
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()])
        )
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            dataStoreFactory: {
                SumiTrackingProtectionDataStore(
                    userDefaults: harness.defaults,
                    storageDirectory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("SumiNormalTabNonCurrentOverride-\(UUID().uuidString)", isDirectory: true)
                )
            },
            contentBlockingServiceFactory: { _, _ in service }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/current",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.setupWebView()
        let controller = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController as? UserContentController
        )
        await controller.awaitContentBlockingAssetsInstalled()
        try await waitForAssets(on: controller) { $0.globalRuleLists.count == 1 }

        let otherURL = URL(string: "https://www.other.example/path")!
        settings.setSiteOverride(.disabled, for: otherURL)
        tab.markTrackingProtectionReloadRequiredIfNeeded(afterChangingOverrideFor: otherURL)

        XCTAssertFalse(tab.isTrackingProtectionReloadRequired)
    }

    func testNormalTabsAfterManualTrackerDataUpdateUseCommittedWorkingRules() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        settings.setGlobalMode(.enabled)
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiNormalTabManualUpdate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storageDirectory) }
        let dataStore = SumiTrackingProtectionDataStore(
            userDefaults: harness.defaults,
            storageDirectory: storageDirectory
        )
        try dataStore.storeDownloadedData(
            Self.trackerDataJSON(domain: "initial-normal-manual.example"),
            etag: "\"initial-normal-manual\""
        )
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            dataStoreFactory: { dataStore },
            contentBlockingServiceFactory: { settings, dataStore in
                SumiContentBlockingService(
                    policy: .disabled,
                    trackingProtectionSettings: settings,
                    trackingRuleSource: SumiEmbeddedDDGTrackerDataRuleSource(dataStore: dataStore),
                    trackingDataStore: dataStore
                )
            }
        )
        let updatedTrackerData = try Self.trackerDataJSON(domain: "updated-normal-manual.example")

        let updateResult = await module.updateTrackerDataManually {
            SumiTrackerDataUpdater(fetch: { request in
                (
                    updatedTrackerData,
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["ETag": "\"updated-normal-manual\""]
                    )!
                )
            })
        }

        guard case .downloaded = updateResult else {
            return XCTFail("Expected downloaded result, got \(updateResult)")
        }
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/after-manual-update",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.setupWebView()
        let controller = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController as? UserContentController
        )
        await controller.awaitContentBlockingAssetsInstalled()
        try await waitForAssets(on: controller) { $0.globalRuleLists.count == 1 }

        let activeDataSet = try dataStore.loadActiveDataSet()
        XCTAssertEqual(activeDataSet.trackerData.trackers.keys.sorted(), ["updated-normal-manual.example"])
        XCTAssertEqual(dataStore.downloadedETag, "\"updated-normal-manual\"")
    }

    func testNormalTabConfigurationCreatesDistinctControllersWithSharedProcessPool() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let first = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://first.example")
        )
        let second = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://second.example")
        )

        XCTAssertFalse(first.userContentController === second.userContentController)
        XCTAssertTrue(first.processPool === second.processPool)
        XCTAssertTrue(first.processPool === browserConfiguration.normalTabProcessPool)
    }

    func testNormalTabConfigurationDoesNotCopyTemplateScripts() async throws {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let templateMarker = "window.__sumiTemplateScriptShouldNotCopy = true;"
        browserConfiguration.webViewConfiguration.userContentController.addUserScript(
            WKUserScript(
                source: templateMarker,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let seedMarker = "window.__sumiManagedProviderScript = true;"
        let scriptsProvider = SumiNormalTabUserScripts(
            managedUserScripts: [TestNormalTabUserScript(source: seedMarker)]
        )
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com"),
            userScriptsProvider: scriptsProvider
        )

        let controller = try XCTUnwrap(configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()

        let sources = configuration.userContentController.userScripts.map(\.source)
        XCTAssertFalse(sources.contains { $0.contains(templateMarker) })
        XCTAssertEqual(sources.filter { $0.contains(seedMarker) }.count, 1)
    }

    func testEphemeralProfileUsesNonPersistentDataStore() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile.createEphemeral()
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://private.example")
        )

        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(configuration.websiteDataStore === profile.dataStore)
    }

    func testAuxiliaryConfigurationsDoNotInstallTabSuspensionBridge() {
        let browserConfiguration = BrowserConfiguration()
        let peekConfiguration = browserConfiguration.auxiliaryWebViewConfiguration(surface: .peek)
        let miniWindowConfiguration = browserConfiguration.auxiliaryWebViewConfiguration(surface: .miniWindow)

        assertNoTabSuspensionBridge(in: peekConfiguration)
        assertNoTabSuspensionBridge(in: miniWindowConfiguration)
    }

    func testAuxiliaryExtensionOptionsConfigurationInstallsNoTrackingRuleLists() async throws {
        let browserConfiguration = BrowserConfiguration()
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )

        let controller = try XCTUnwrap(configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertFalse(controller.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
    }

    func testAuxiliaryAndFaviconPathsDoNotAccessTrackingRuntime() throws {
        for relativePath in [
            "Sumi/Managers/PeekManager/PeekWebView.swift",
            "Sumi/Components/MiniWindow/MiniWindowWebView.swift",
            "Sumi/Favicons/DDG/Model/FaviconDownloader.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("trackingProtectionModule"), relativePath)
            XCTAssertFalse(source.contains("contentBlockingServiceIfEnabled"), relativePath)
            XCTAssertFalse(source.contains("SumiContentBlockingService"), relativePath)
            XCTAssertFalse(source.contains("SumiTrackingProtectionSettings"), relativePath)
            XCTAssertFalse(source.contains("SumiTrackingProtectionDataStore"), relativePath)
        }
    }

    func testCacheOptimizedConfigurationIsAuxiliaryOnly() {
        let browserConfiguration = BrowserConfiguration()
        let configuration = browserConfiguration.cacheOptimizedWebViewConfiguration()

        assertNoTabSuspensionBridge(in: configuration)
    }

    func testNormalTabConfigurationInstallsCoreScriptProvider() throws {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let tab = Tab(url: URL(string: "https://example.com/core")!)
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: tab.url,
            userScriptsProvider: tab.normalTabUserScriptsProvider(for: tab.url)
        )

        let provider = try XCTUnwrap(configuration.userContentController.sumiNormalTabUserScriptsProvider)
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiIdentity_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("__sumiTabSuspension"))
    }

    func testTabSuspensionBridgeScriptIsMainFrameOnly() throws {
        let tab = Tab(name: "Bridge")
        let bridgeScript = try XCTUnwrap(
            tab.normalTabCoreUserScripts().first { script in
                script.source.contains("__sumiTabSuspension")
            }
        )

        XCTAssertTrue(bridgeScript.source.contains("sumiTabSuspension_"))
        XCTAssertTrue(bridgeScript.source.contains("tabSuspension"))
        XCTAssertTrue(bridgeScript.forMainFrameOnly)
    }

    func testPrimaryTabSetupUsesCentralFactoryNotFaviconOnlyFactoryOrScriptRemoval() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sumi/Models/Tab/Tab+WebViewRuntime.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("normalTabWebViewConfiguration"))
        XCTAssertFalse(source.contains("SumiDDGFaviconUserContentControllerFactory"))
        XCTAssertFalse(source.contains("removeAllUserScripts"))

        let lifecycleSourceURL = repoRoot
            .appendingPathComponent("Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift")
        let lifecycleSource = try String(contentsOf: lifecycleSourceURL, encoding: .utf8)
        XCTAssertFalse(lifecycleSource.contains("injectDocumentIdleScripts"))
        XCTAssertFalse(lifecycleSource.contains("evaluateJavaScript"))
    }

    func testCoordinatorDoesNotCreateNormalWebViewsOrFallbackToPeek() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("createWebViewInternal"))
        XCTAssertFalse(source.contains("normalTabWebViewConfiguration"))
        XCTAssertFalse(source.contains("auxiliaryWebViewConfiguration"))
        XCTAssertFalse(source.contains("surface: .peek"))
        XCTAssertFalse(source.contains("FocusableWKWebView(frame: .zero"))
        XCTAssertTrue(source.contains("tab.ensureWebView()"))
        XCTAssertTrue(source.contains("tab.makeNormalTabWebView"))
    }

    private func assertNoTabSuspensionBridge(
        in configuration: WKWebViewConfiguration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = configuration.userContentController.userScripts
            .map(\.source)
            .joined(separator: "\n")

        XCTAssertFalse(source.contains("__sumiTabSuspension"), file: file, line: line)
        XCTAssertFalse(source.contains("sumiTabSuspension_"), file: file, line: line)
        XCTAssertFalse(source.contains("tabSuspension"), file: file, line: line)
    }

    private func makeProbeTrackingModule(
        registry: SumiModuleRegistry,
        probe: NormalTabTrackingRuntimeProbe,
        defaults: UserDefaults,
        service: SumiContentBlockingService? = nil
    ) -> SumiTrackingProtectionModule {
        SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                probe.settingsCount += 1
                return SumiTrackingProtectionSettings(userDefaults: defaults)
            },
            dataStoreFactory: {
                probe.dataStoreCount += 1
                return SumiTrackingProtectionDataStore(
                    userDefaults: defaults,
                    storageDirectory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("SumiNormalTabTrackingRuntime-\(UUID().uuidString)", isDirectory: true)
                )
            },
            contentBlockingServiceFactory: { _, _ in
                probe.serviceCount += 1
                return service ?? SumiContentBlockingService(policy: .disabled)
            }
        )
    }

    private static func validRuleListDefinition() -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: "SumiNormalTabTrackingTestRules-\(UUID().uuidString)",
            encodedContentRuleList: """
            [
              {
                "trigger": {
                  "url-filter": ".*normal-tab-blocked\\\\.example/.*"
                },
                "action": {
                  "type": "block"
                }
              }
            ]
            """
        )
    }

    private static func trackerDataJSON(domain: String) throws -> Data {
        let ownerName = "Tracker Example"
        let tracker = KnownTracker(
            domain: domain,
            defaultAction: .block,
            owner: KnownTracker.Owner(
                name: ownerName,
                displayName: ownerName,
                ownedBy: nil
            ),
            prevalence: 1,
            subdomains: nil,
            categories: ["Analytics"],
            rules: nil
        )
        let entity = Entity(
            displayName: ownerName,
            domains: [domain],
            prevalence: 1
        )
        let trackerData = TrackerData(
            trackers: [domain: tracker],
            entities: [ownerName: entity],
            domains: [domain: ownerName],
            cnames: nil
        )
        return try JSONEncoder().encode(trackerData)
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
        XCTFail("Timed out waiting for normal-tab content-blocking assets")
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

@MainActor
private final class NormalTabTrackingRuntimeProbe {
    var settingsCount = 0
    var dataStoreCount = 0
    var serviceCount = 0
}

private final class TestNormalTabUserScript: NSObject, UserScript {
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = false
    let messageNames: [String] = []

    init(source: String) {
        self.source = source
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}
