import BrowserServicesKit
import SwiftData
import TrackerRadarKit
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
        XCTAssertTrue(configuration.sumiIsNormalTabWebViewConfiguration)
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

    func testBrowserManagerStartupWithUserscriptsDisabledDoesNotInitializeUserscriptsRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabUserscriptsRuntimeProbe()
        let module = makeProbeUserscriptsModule(
            registry: registry,
            probe: probe
        )

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            userscriptsModule: module
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertFalse(registry.isEnabled(.userScripts))
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertEqual(probe.injectorCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testBrowserManagerStartupWithExtensionsDisabledDoesNotInitializeExtensionsRuntime() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabExtensionsRuntimeProbe()
        let container = try Self.makeInMemoryExtensionContainer()
        let module = makeProbeExtensionsModule(
            registry: registry,
            probe: probe,
            context: container.mainContext
        )

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: module
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertFalse(registry.isEnabled(.extensions))
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertTrue(browserManager.extensionSurfaceStore.installedExtensions.isEmpty)
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

    func testTabNormalWebViewCreationWithUserscriptsDisabledDoesNotInitializeUserscriptsRuntime() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabUserscriptsRuntimeProbe()
        let module = makeProbeUserscriptsModule(
            registry: registry,
            probe: probe
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            userscriptsModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/userscripts-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let webView = try XCTUnwrap(tab.existingWebView)
        let controller = try XCTUnwrap(webView.configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(
            webView.configuration.userContentController.sumiNormalTabUserScriptsProvider
        )
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiIdentity_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertFalse(sources.contains(UserScriptInjector.userScriptMarker))
        XCTAssertFalse(sources.contains("sumiGM_"))
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertEqual(probe.injectorCount, 0)
    }

    func testTabNormalWebViewCreationWithExtensionsDisabledDoesNotInitializeExtensionsRuntime() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabExtensionsRuntimeProbe()
        let container = try Self.makeInMemoryExtensionContainer()
        let module = makeProbeExtensionsModule(
            registry: registry,
            probe: probe,
            context: container.mainContext
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/extensions-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let webView = try XCTUnwrap(tab.existingWebView)
        let controller = try XCTUnwrap(webView.configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(
            webView.configuration.userContentController.sumiNormalTabUserScriptsProvider
        )
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiIdentity_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertFalse(sources.contains("SUMI_EC_PAGE_BRIDGE:"))
        XCTAssertFalse(sources.contains("sumiExternallyConnectableRuntime"))
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
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

    func testNormalTabConfigurationCreatesDistinctMarkedControllers() {
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
        XCTAssertTrue(first.sumiIsNormalTabWebViewConfiguration)
        XCTAssertTrue(second.sumiIsNormalTabWebViewConfiguration)
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

    func testNormalTabConfigurationsShareVisitedLinkStoreWithinProfile() throws {
        let provider = SharedVisitedLinkStoreProvider()
        let browserConfiguration = BrowserConfiguration(
            visitedLinkStoreProvider: provider
        )
        let profile = Profile(name: "Shared Links")

        let first = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://first.example")
        )
        let second = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://second.example")
        )

        let firstStore = try XCTUnwrap(first.sumiVisitedLinkStoreObject)
        let secondStore = try XCTUnwrap(second.sumiVisitedLinkStoreObject)
        XCTAssertTrue(firstStore === secondStore)
    }

    func testNormalTabConfigurationsSeparateVisitedLinkStoresAcrossProfiles() throws {
        let provider = SharedVisitedLinkStoreProvider()
        let browserConfiguration = BrowserConfiguration(
            visitedLinkStoreProvider: provider
        )
        let firstProfile = Profile(name: "First")
        let secondProfile = Profile(name: "Second")

        let first = browserConfiguration.normalTabWebViewConfiguration(
            for: firstProfile,
            url: URL(string: "https://first.example")
        )
        let second = browserConfiguration.normalTabWebViewConfiguration(
            for: secondProfile,
            url: URL(string: "https://second.example")
        )

        let firstStore = try XCTUnwrap(first.sumiVisitedLinkStoreObject)
        let secondStore = try XCTUnwrap(second.sumiVisitedLinkStoreObject)
        XCTAssertFalse(firstStore === secondStore)
    }

    func testEphemeralProfilesUseIsolatedVisitedLinkStores() throws {
        let provider = SharedVisitedLinkStoreProvider()
        let browserConfiguration = BrowserConfiguration(
            visitedLinkStoreProvider: provider
        )
        let persistentProfile = Profile(name: "Persistent")
        let firstEphemeralProfile = Profile.createEphemeral()
        let secondEphemeralProfile = Profile.createEphemeral()

        let persistent = browserConfiguration.normalTabWebViewConfiguration(
            for: persistentProfile,
            url: URL(string: "https://persistent.example")
        )
        let firstEphemeral = browserConfiguration.normalTabWebViewConfiguration(
            for: firstEphemeralProfile,
            url: URL(string: "https://private-a.example")
        )
        let secondEphemeral = browserConfiguration.normalTabWebViewConfiguration(
            for: secondEphemeralProfile,
            url: URL(string: "https://private-b.example")
        )

        let persistentStore = try XCTUnwrap(persistent.sumiVisitedLinkStoreObject)
        let firstEphemeralStore = try XCTUnwrap(firstEphemeral.sumiVisitedLinkStoreObject)
        let secondEphemeralStore = try XCTUnwrap(secondEphemeral.sumiVisitedLinkStoreObject)
        XCTAssertFalse(persistentStore === firstEphemeralStore)
        XCTAssertFalse(firstEphemeralStore === secondEphemeralStore)
    }

    func testProfileAwareAuxiliaryConfigurationCarriesStoreWithoutEnablingRecording() throws {
        let provider = SharedVisitedLinkStoreProvider()
        let browserConfiguration = BrowserConfiguration(
            visitedLinkStoreProvider: provider
        )
        let profile = Profile(name: "Auxiliary")
        let normal = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://normal.example")
        )
        let auxiliary = browserConfiguration.auxiliaryWebViewConfiguration(
            for: profile,
            surface: .glance
        )

        let normalStore = try XCTUnwrap(normal.sumiVisitedLinkStoreObject)
        let auxiliaryStore = try XCTUnwrap(auxiliary.sumiVisitedLinkStoreObject)
        XCTAssertTrue(normalStore === auxiliaryStore)

        _ = WKWebView(frame: .zero, configuration: auxiliary)
    }

    func testProfilelessAuxiliaryConfigurationDoesNotReceiveDefaultProfileVisitedLinkStore() throws {
        let provider = SharedVisitedLinkStoreProvider()
        let browserConfiguration = BrowserConfiguration(
            visitedLinkStoreProvider: provider
        )
        let profile = Profile(name: "Default")
        let normal = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://normal.example")
        )
        let auxiliary = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .faviconDownload
        )

        XCTAssertFalse(auxiliary.websiteDataStore.isPersistent)
        let normalStore = try XCTUnwrap(normal.sumiVisitedLinkStoreObject)
        let auxiliaryStore = try XCTUnwrap(auxiliary.sumiVisitedLinkStoreObject)
        XCTAssertFalse(normalStore === auxiliaryStore)

        _ = WKWebView(frame: .zero, configuration: auxiliary)
    }

    func testAuxiliaryConfigurationsDoNotInstallTabSuspensionBridge() {
        let browserConfiguration = BrowserConfiguration()
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .faviconDownload),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .miniWindow),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
        ]

        configurations.forEach { configuration in
            assertNoTabSuspensionBridge(in: configuration)
        }
    }

    func testAuxiliaryConfigurationsUsePlainLightweightControllers() {
        let browserConfiguration = BrowserConfiguration()
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .faviconDownload),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .miniWindow),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
        ]

        for configuration in configurations {
            XCTAssertFalse(configuration.userContentController is UserContentController)
            XCTAssertFalse(
                configuration.userContentController
                    .sumiUsesNormalTabBrowserServicesKitUserContentController
            )
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserScriptsProvider)
            XCTAssertTrue(configuration.userContentController.userScripts.isEmpty)
            XCTAssertNil(configuration.webExtensionController)
        }
    }

    func testFaviconDownloadAuxiliaryConfigurationIsEphemeralAndJavaScriptDisabled() {
        let browserConfiguration = BrowserConfiguration()
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .faviconDownload
        )

        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertTrue(configuration.userContentController.userScripts.isEmpty)
    }

    func testProfileAwareAuxiliaryConfigurationsPreserveProfileDataStore() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Auxiliary Profile")
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(
                for: profile,
                surface: .glance
            ),
            browserConfiguration.auxiliaryWebViewConfiguration(
                for: profile,
                surface: .miniWindow
            ),
            browserConfiguration.auxiliaryWebViewConfiguration(
                for: profile,
                surface: .extensionOptions
            ),
        ]

        for configuration in configurations {
            XCTAssertTrue(configuration.websiteDataStore === profile.dataStore)
        }
    }

    func testAuxiliaryExtensionOptionsConfigurationUsesNoContentBlockingInfrastructure() {
        let browserConfiguration = BrowserConfiguration()
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )

        XCTAssertFalse(configuration.userContentController is UserContentController)
        XCTAssertFalse(
            configuration.userContentController
                .sumiUsesNormalTabBrowserServicesKitUserContentController
        )
        XCTAssertNil(configuration.userContentController.sumiNormalTabUserScriptsProvider)
        XCTAssertTrue(configuration.userContentController.userScripts.isEmpty)
    }

    func testAuxiliaryConfigurationsInstallNoUserscriptRuntimeContributions() {
        let browserConfiguration = BrowserConfiguration()
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .faviconDownload),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .miniWindow),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
        ]

        for configuration in configurations {
            let sources = configuration.userContentController.userScripts
                .map(\.source)
                .joined(separator: "\n")
            XCTAssertFalse(sources.contains(UserScriptInjector.userScriptMarker))
            XCTAssertFalse(sources.contains("SUMI_USER_SCRIPT_RUNTIME"))
            XCTAssertFalse(sources.contains("sumiGM_"))
            XCTAssertFalse(sources.contains("data-sumi-userscript"))
            XCTAssertFalse(sources.contains("sumiLinkInteraction_"))
            XCTAssertFalse(sources.contains("sumiIdentity_"))
            XCTAssertFalse(sources.contains("SUMI_EC_PAGE_BRIDGE:"))
            XCTAssertFalse(sources.contains("sumiExternallyConnectableRuntime"))
        }
    }

    func testAuxiliaryConfigurationFiltersNormalTabAndOptionalRuntimeScripts() {
        let browserConfiguration = BrowserConfiguration()
        let sourceConfiguration = WKWebViewConfiguration()
        let allowedScript = WKUserScript(
            source: "window.__sumiExtensionOptionsAllowedScript = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let blockedScripts = [
            "__sumiDDGFaviconTransportInstalled",
            "__sumiTabSuspension",
            "SUMI_USER_SCRIPT_RUNTIME",
            "SUMI_EC_PAGE_BRIDGE:",
            UserScriptInjector.userScriptMarker,
            "sumiExternallyConnectableRuntime",
            "sumiFavicons",
            "sumiGM_",
            "sumiIdentity_",
            "sumiLinkInteraction_",
            "sumiTabSuspension_",
        ].map { marker in
            WKUserScript(
                source: "/* \(marker) */",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        }

        ([allowedScript] + blockedScripts).forEach {
            sourceConfiguration.userContentController.addUserScript($0)
        }

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            from: sourceConfiguration,
            surface: .extensionOptions,
            additionalUserScripts: sourceConfiguration.userContentController.userScripts
        )
        let sources = configuration.userContentController.userScripts
            .map(\.source)
            .joined(separator: "\n")

        XCTAssertTrue(sources.contains("__sumiExtensionOptionsAllowedScript"))
        XCTAssertEqual(configuration.userContentController.userScripts.count, 1)
        for blockedMarker in [
            "__sumiDDGFaviconTransportInstalled",
            "__sumiTabSuspension",
            "SUMI_USER_SCRIPT_RUNTIME",
            "SUMI_EC_PAGE_BRIDGE:",
            UserScriptInjector.userScriptMarker,
            "sumiExternallyConnectableRuntime",
            "sumiFavicons",
            "sumiGM_",
            "sumiIdentity_",
            "sumiLinkInteraction_",
            "sumiTabSuspension_",
        ] {
            XCTAssertFalse(sources.contains(blockedMarker), blockedMarker)
        }
    }

    func testAuxiliaryAndFaviconPathsDoNotAccessTrackingRuntime() throws {
        for relativePath in [
            "Sumi/Managers/GlanceManager/GlanceWebView.swift",
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

    func testAuxiliaryAndFaviconPathsDoNotAccessUserscriptsRuntime() throws {
        for relativePath in [
            "Sumi/Managers/GlanceManager/GlanceWebView.swift",
            "Sumi/Components/MiniWindow/MiniWindowWebView.swift",
            "Sumi/Favicons/DDG/Model/FaviconDownloader.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("userscriptsModule"), relativePath)
            XCTAssertFalse(source.contains("SumiUserscriptsModule"), relativePath)
            XCTAssertFalse(source.contains("SumiScriptsManager("), relativePath)
            XCTAssertFalse(source.contains("UserScriptStore("), relativePath)
            XCTAssertFalse(source.contains("UserScriptInjector("), relativePath)
        }
    }

    func testAuxiliaryAndFaviconPathsDoNotAccessExtensionsRuntime() throws {
        for relativePath in [
            "Sumi/Managers/GlanceManager/GlanceWebView.swift",
            "Sumi/Components/MiniWindow/MiniWindowWebView.swift",
            "Sumi/Favicons/DDG/Model/FaviconDownloader.swift",
            "Sumi/Models/BrowserConfig/BrowserConfig.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("extensionsModule"), relativePath)
            XCTAssertFalse(source.contains("SumiExtensionsModule"), relativePath)
            XCTAssertFalse(source.contains("ExtensionManager("), relativePath)
            XCTAssertFalse(source.contains("NativeMessagingHandler("), relativePath)
        }

        let tabRuntimeSource = try Self.source(named: "Sumi/Models/Tab/Tab+WebViewRuntime.swift")
        XCTAssertTrue(tabRuntimeSource.contains("extensionsModule.prepareWebViewConfigurationForExtensionRuntime"))
        XCTAssertTrue(tabRuntimeSource.contains("extensionsModule.normalTabUserScripts()"))
        XCTAssertFalse(tabRuntimeSource.contains("ExtensionManager("))
        XCTAssertFalse(tabRuntimeSource.contains("NativeMessagingHandler("))
    }

    func testAuxiliarySurfacesDoNotUseNormalTabConfiguration() throws {
        let faviconSource = try Self.source(named: "Sumi/Favicons/DDG/Model/FaviconDownloader.swift")
        XCTAssertTrue(faviconSource.contains("auxiliaryWebViewConfiguration"))
        XCTAssertTrue(faviconSource.contains("surface: .faviconDownload"))
        XCTAssertFalse(faviconSource.contains("WKWebViewConfiguration()"))
        XCTAssertFalse(faviconSource.contains("normalTabWebViewConfiguration("))

        for relativePath in [
            "Sumi/Managers/GlanceManager/GlanceWebView.swift",
            "Sumi/Components/MiniWindow/MiniWindowWebView.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertTrue(source.contains("auxiliaryWebViewConfiguration"), relativePath)
            XCTAssertFalse(source.contains("normalTabWebViewConfiguration("), relativePath)
        }
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

    func testCoordinatorDoesNotCreateNormalWebViewsOrFallbackToGlance() throws {
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
        XCTAssertFalse(source.contains("surface: .glance"))
        XCTAssertFalse(source.contains("FocusableWKWebView(frame: .zero"))
        XCTAssertTrue(source.contains("tab.ensureWebView()"))
        XCTAssertTrue(source.contains("tab.makeNormalTabWebView"))
    }

    func testBrowserConfigurationDoesNotExposeLegacyCompatibilityAliases() throws {
        let source = try Self.source(named: "Sumi/Models/BrowserConfig/BrowserConfig.swift")

        XCTAssertFalse(source.contains("cacheOptimizedWebViewConfiguration"))
        XCTAssertFalse(source.contains("webViewConfiguration(for:"))
    }

    func testBrowserManagerDoesNotConstructSumiScriptsManagerAtStartup() throws {
        let source = try Self.source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")

        XCTAssertTrue(source.contains("let userscriptsModule: SumiUserscriptsModule"))
        XCTAssertTrue(source.contains("self.userscriptsModule.attach(browserManager: self)"))
        XCTAssertFalse(source.contains("let sumiScriptsManager"))
        XCTAssertFalse(source.contains("self.sumiScriptsManager"))
        XCTAssertFalse(source.contains("SumiScriptsManager("))
    }

    func testBrowserManagerDoesNotConstructExtensionManagerAtStartup() throws {
        let source = try Self.source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")

        XCTAssertTrue(source.contains("let extensionsModule: SumiExtensionsModule"))
        XCTAssertTrue(source.contains("self.extensionsModule.attach(browserManager: self)"))
        XCTAssertFalse(source.contains("let extensionManager"))
        XCTAssertFalse(source.contains("self.extensionManager"))
        XCTAssertFalse(source.contains("ExtensionManager("))
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

    private func makeProbeUserscriptsModule(
        registry: SumiModuleRegistry,
        probe: NormalTabUserscriptsRuntimeProbe
    ) -> SumiUserscriptsModule {
        SumiUserscriptsModule(
            moduleRegistry: registry,
            managerFactory: { context in
                probe.managerCount += 1
                return SumiScriptsManager(
                    context: context,
                    storeFactory: { context in
                        probe.storeCount += 1
                        return UserScriptStore(
                            directory: FileManager.default.temporaryDirectory
                                .appendingPathComponent(
                                    "SumiNormalTabUserscripts-\(UUID().uuidString)",
                                    isDirectory: true
                                ),
                            context: context
                        )
                    },
                    injectorFactory: {
                        probe.injectorCount += 1
                        return UserScriptInjector()
                    }
                )
            }
        )
    }

    private func makeProbeExtensionsModule(
        registry: SumiModuleRegistry,
        probe: NormalTabExtensionsRuntimeProbe,
        context: ModelContext
    ) -> SumiExtensionsModule {
        SumiExtensionsModule(
            moduleRegistry: registry,
            context: context,
            managerFactory: { context, initialProfile, browserConfiguration in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
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

    private static func makeInMemoryExtensionContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

@MainActor
private final class NormalTabTrackingRuntimeProbe {
    var settingsCount = 0
    var dataStoreCount = 0
    var serviceCount = 0
}

private final class NormalTabUserscriptsRuntimeProbe {
    var managerCount = 0
    var storeCount = 0
    var injectorCount = 0
}

private final class NormalTabExtensionsRuntimeProbe {
    var managerCount = 0
}

private final class TestNormalTabUserScript: NSObject, SumiUserScript {
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
