import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserConfigurationNormalTabTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    private func makeUnloadedNormalTabWebView(
        for tab: Tab,
        reason: String
    ) throws -> WKWebView {
        let webView = try XCTUnwrap(tab.makeNormalTabWebView(reason: reason))
        tab._webView = webView
        return webView
    }

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testNormalTabConfigurationUsesSumiNormalTabControllerAndProfileStore() async throws {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")
        )

        let controller = try XCTUnwrap(configuration.userContentController.sumiNormalTabUserContentController)
        XCTAssertTrue(configuration.sumiIsNormalTabWebViewConfiguration)
        XCTAssertTrue(configuration.websiteDataStore === profile.dataStore)
        XCTAssertTrue(controller.wkUserContentController === configuration.userContentController)
        XCTAssertNotNil(controller.normalTabUserScriptsProvider)
        XCTAssertTrue(controller.hasInstalledInitialUserContent)
        XCTAssertFalse(configuration.userContentController.userScripts.isEmpty)
        let appName = configuration.applicationNameForUserAgent
        XCTAssertNotNil(appName)
        XCTAssertTrue(appName?.hasPrefix("Version/") ?? false)
        XCTAssertTrue(appName?.contains(" Safari/") ?? false)

        await controller.waitForContentBlockingAssetsInstalled()

        let contentBlockingSummary = controller.contentBlockingAssetSummary
        XCTAssertTrue(contentBlockingSummary.isInstalled)
        XCTAssertFalse(controller.wkUserContentController.userScripts.isEmpty)
        XCTAssertEqual(contentBlockingSummary.globalRuleListCount, 0)
    }

    func testBrowserManagerStartupWithProtectionOffDoesNotInitializePreparedBundleRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)
        let protectionCoordinator = SumiProtectionCoordinator(
            settings: SumiProtectionSettings(userDefaults: harness.defaults),
            adBlockingModule: adBlockingModule,
            moduleRegistry: registry
        )

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertFalse(adBlockingModule.hasLoadedRuntime)
    }

    func testStartupNormalTabMaterializationWaitsOnlyWhileProtectionRestoreIsPending() {
        XCTAssertFalse(
            StartupNormalTabMaterializationPolicy.shouldDefer(
                appliedProtectionLevel: .off,
                hasFinishedStartupProtectionRestore: false
            )
        )
        XCTAssertTrue(
            StartupNormalTabMaterializationPolicy.shouldDefer(
                appliedProtectionLevel: .protection,
                hasFinishedStartupProtectionRestore: false
            )
        )
        XCTAssertTrue(
            StartupNormalTabMaterializationPolicy.shouldDefer(
                appliedProtectionLevel: .adblock,
                hasFinishedStartupProtectionRestore: false
            )
        )
        XCTAssertFalse(
            StartupNormalTabMaterializationPolicy.shouldDefer(
                appliedProtectionLevel: .adblock,
                hasFinishedStartupProtectionRestore: true
            )
        )
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

    func testTabNormalWebViewCreationWithProtectionOffDoesNotLoadOrAttachPreparedRules() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let protection = try makeProtectionCoordinator(
            defaults: harness.defaults,
            registry: registry,
            level: .off
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: protection.adBlockingModule,
            protectionCoordinator: protection.coordinator
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/tracking-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.protectionOff"
        )
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertFalse(controller.contentBlockingAssetSummary.isContentBlockingFeatureEnabled)
        XCTAssertFalse(protection.adBlockingModule.hasLoadedRuntime)
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

        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.userscriptsDisabled"
        )
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(controller.normalTabUserScriptsProvider)
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

        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.extensionsDisabled"
        )
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(controller.normalTabUserScriptsProvider)
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

    func testPreparedTrackingNetworkAttachesRulesAndDisableBlocksFutureNormalTabsAfterRestart() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let protection = try makeProtectionCoordinator(
            defaults: harness.defaults,
            registry: registry,
            level: .protection
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: protection.adBlockingModule,
            protectionCoordinator: protection.coordinator
        )
        _ = try await protection.coordinator.restoreAppliedLevelForStartup()

        let enabledTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/tracking-enabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let enabledWebView = try makeUnloadedNormalTabWebView(
            for: enabledTab,
            reason: "BrowserConfigurationNormalTabTests.trackingEnabled"
        )
        let enabledController = try XCTUnwrap(
            enabledWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await enabledController.waitForContentBlockingAssetsInstalled()
        try await waitForAssets(on: enabledController) { $0.globalRuleListCount == 1 }

        protection.coordinator.setLevel(.off)
        _ = try await protection.coordinator.applySelectedLevel()
        XCTAssertTrue(protection.coordinator.settings.browserRestartRequired)
        _ = try await protection.coordinator.restoreAppliedLevelForStartup()
        let disabledTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/tracking-disabled-after-toggle",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let disabledWebView = try makeUnloadedNormalTabWebView(
            for: disabledTab,
            reason: "BrowserConfigurationNormalTabTests.trackingDisabledAfterToggle"
        )
        let disabledController = try XCTUnwrap(
            disabledWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await disabledController.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(disabledController.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertTrue(disabledController.contentBlockingAssetSummary.globalRuleListIdentifiers.filter { $0.hasPrefix("sumi.") }.isEmpty)
    }

    func testPreparedTrackingNetworkWithSiteDisabledAttachesNoRulesAndNoService() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let protection = try makeProtectionCoordinator(
            defaults: harness.defaults,
            registry: registry,
            level: .protection
        )
        protection.coordinator.setSiteOverride(.disabled, for: URL(string: "https://www.example.com/path")!)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: protection.adBlockingModule,
            protectionCoordinator: protection.coordinator
        )

        let tab = browserManager.tabManager.createNewTab(
            url: "https://sub.example.com/site-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.siteDisabled"
        )
        let controller = try XCTUnwrap(
            webView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertEqual(tab.protectionAppliedAttachmentState?.effectiveLevel, .off)
        XCTAssertEqual(tab.protectionAppliedAttachmentState?.activeGroups, [])
    }

    func testSiteOverrideChangeMarksReloadRequiredAndManualRebuildAppliesPolicy() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let protection = try makeProtectionCoordinator(
            defaults: harness.defaults,
            registry: registry,
            level: .protection
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: protection.adBlockingModule,
            protectionCoordinator: protection.coordinator
        )
        _ = try await protection.coordinator.restoreAppliedLevelForStartup()
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/reload-required",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let originalWebView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.reloadRequired"
        )
        let originalController = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await originalController.waitForContentBlockingAssetsInstalled()
        try await waitForAssets(on: originalController) { $0.globalRuleListCount == 1 }

        protection.coordinator.setSiteOverride(.disabled, for: tab.url)
        tab.markProtectionReloadRequiredIfNeeded(afterChangingPolicyFor: tab.url)

        XCTAssertTrue(tab.isProtectionReloadRequired)
        XCTAssertTrue(tab.existingWebView === originalWebView)

        XCTAssertTrue(
            tab.rebuildNormalWebViewForProtectionIfNeeded(
                targetURL: tab.url,
                reason: "BrowserConfigurationNormalTabTests.manualReload"
            )
        )
        let rebuiltWebView = try XCTUnwrap(tab.existingWebView)
        XCTAssertFalse(rebuiltWebView === originalWebView)
        let rebuiltController = try XCTUnwrap(
            rebuiltWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await rebuiltController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(rebuiltController.contentBlockingAssetSummary.globalRuleListCount, 0)

        tab.clearProtectionReloadRequirementIfResolved(for: tab.url)
        XCTAssertFalse(tab.isProtectionReloadRequired)
    }

    func testApplyingGlobalProtectionLevelRequiresRestartAndManualReloadDoesNotApplyPlan() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let protection = try makeProtectionCoordinator(
            defaults: harness.defaults,
            registry: registry,
            level: .off
        )
        let targetURL = URL(string: "https://www.example.com/apply-level")!
        let initialDecision = protection.coordinator.normalTabDecision(
            for: targetURL,
            profileId: nil
        )
        XCTAssertEqual(initialDecision.plan.effectiveLevel, .off)
        XCTAssertNil(initialDecision.contentBlockingService)

        protection.coordinator.setLevel(.protection)
        _ = try await protection.coordinator.applySelectedLevel()
        XCTAssertTrue(protection.coordinator.settings.browserRestartRequired)
        XCTAssertFalse(protection.coordinator.applyNeeded)
        let protectionDecision = protection.coordinator.normalTabDecision(
            for: targetURL,
            profileId: nil
        )
        XCTAssertEqual(protectionDecision.plan.effectiveLevel, .off)
        XCTAssertTrue(protectionDecision.plan.activeGroups.isEmpty)
        XCTAssertNil(protectionDecision.contentBlockingService)

        _ = try await protection.coordinator.restoreAppliedLevelForStartup()
        XCTAssertFalse(protection.coordinator.settings.browserRestartRequired)
        let restartedDecision = protection.coordinator.normalTabDecision(
            for: URL(string: "https://www.example.com/after-restart")!,
            profileId: nil
        )
        XCTAssertEqual(restartedDecision.plan.effectiveLevel, .protection)
        XCTAssertEqual(restartedDecision.plan.activeGroups, [.trackingNetwork])
        XCTAssertNotNil(restartedDecision.contentBlockingService)
    }

    func testOffProtectionLevelKeepsNewTabHotPathEmptyAfterRestart() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let protection = try makeProtectionCoordinator(
            defaults: harness.defaults,
            registry: registry,
            level: .protection
        )
        var browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: protection.adBlockingModule,
            protectionCoordinator: protection.coordinator
        )
        _ = try await protection.coordinator.restoreAppliedLevelForStartup()

        protection.coordinator.setLevel(.off)
        _ = try await protection.coordinator.applySelectedLevel()
        XCTAssertTrue(protection.coordinator.settings.browserRestartRequired)

        let restartedCoordinator = SumiProtectionCoordinator(
            settings: protection.coordinator.settings,
            adBlockingModule: protection.adBlockingModule,
            moduleRegistry: registry
        )
        browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: protection.adBlockingModule,
            protectionCoordinator: restartedCoordinator
        )
        _ = try await restartedCoordinator.restoreAppliedLevelForStartup()
        XCTAssertFalse(restartedCoordinator.settings.browserRestartRequired)
        XCTAssertFalse(registry.isEnabled(.trackingProtection))
        XCTAssertFalse(registry.isEnabled(.adBlocking))

        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/off-after-restart",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.offAfterRestart"
        )
        let controller = try XCTUnwrap(
            webView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertTrue(controller.contentBlockingAssetSummary.globalRuleListIdentifiers.filter { $0.hasPrefix("sumi.") }.isEmpty)
        XCTAssertEqual(tab.protectionAppliedAttachmentState?.effectiveLevel, .off)
    }

    func testChangingOverrideForNonCurrentSiteDoesNotMarkReloadRequired() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let protection = try makeProtectionCoordinator(
            defaults: harness.defaults,
            registry: registry,
            level: .protection
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: protection.adBlockingModule,
            protectionCoordinator: protection.coordinator
        )
        _ = try await protection.coordinator.restoreAppliedLevelForStartup()
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/current",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.nonCurrentOverride"
        )
        let controller = try XCTUnwrap(
            webView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()
        try await waitForAssets(on: controller) { $0.globalRuleListCount == 1 }

        let otherURL = URL(string: "https://www.other.example/path")!
        protection.coordinator.setSiteOverride(.disabled, for: otherURL)
        tab.markProtectionReloadRequiredIfNeeded(afterChangingPolicyFor: otherURL)

        XCTAssertFalse(tab.isProtectionReloadRequired)
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

        let controller = try XCTUnwrap(configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()

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
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserContentController)
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

        XCTAssertNil(configuration.userContentController.sumiNormalTabUserContentController)
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
            SumiTransientChromeInteractionShieldUserScript.sourceMarker,
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
            SumiTransientChromeInteractionShieldUserScript.sourceMarker,
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
            "Sumi/Components/MiniWindow/MiniWindowWebView.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertTrue(source.contains("auxiliaryWebViewConfiguration"), relativePath)
            XCTAssertFalse(source.contains("normalTabWebViewConfiguration("), relativePath)
        }
    }

    func testGlancePreviewUsesTransientNormalTabRuntimeInsteadOfAuxiliarySurface() throws {
        let managerSource = try Self.source(named: "Sumi/Managers/GlanceManager/GlanceManager.swift")
        let sessionSource = try Self.source(named: "Sumi/Managers/GlanceManager/GlanceSession.swift")

        XCTAssertTrue(managerSource.contains("previewTab.ensureWebView()"))
        XCTAssertTrue(sessionSource.contains("let previewTab: Tab"))
        XCTAssertFalse(managerSource.contains("auxiliaryWebViewConfiguration"))
        XCTAssertFalse(managerSource.contains("surface: .glance"))
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

        let linkInteractionScript = try XCTUnwrap(
            provider.userScripts.first { $0.source.contains("sumiLinkInteraction_\(tab.id.uuidString)") }
        )
        let contextMenuScript = try XCTUnwrap(
            provider.userScripts.first { $0.source.contains("sumiWebPageContextMenu_\(tab.id.uuidString)") }
        )
        let notificationScript = try XCTUnwrap(
            provider.userScripts.first { $0.source.contains("sumiWebNotifications_\(tab.id.uuidString)") }
        )

        XCTAssertFalse(linkInteractionScript.requiresRunInPageContentWorld)
        XCTAssertFalse(contextMenuScript.requiresRunInPageContentWorld)
        XCTAssertEqual(linkInteractionScript.injectionTime, .atDocumentEnd)
        XCTAssertEqual(contextMenuScript.injectionTime, .atDocumentEnd)
        XCTAssertTrue(notificationScript.requiresRunInPageContentWorld)
        XCTAssertFalse(
            notificationScript.source.contains("\n            refreshPermission();\n        })();")
        )
        XCTAssertFalse(configuration.userContentController.userScripts.contains { script in
            script.source.contains("_duckduckgoloader_")
        })
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

    private func makeProtectionCoordinator(
        defaults: UserDefaults,
        registry: SumiModuleRegistry,
        level: SumiProtectionLevel
    ) throws -> (adBlockingModule: SumiAdBlockingModule, coordinator: SumiProtectionCoordinator) {
        let protectionSettings = SumiProtectionSettings(userDefaults: defaults)
        protectionSettings.setLevel(level)
        protectionSettings.setAppliedLevel(level)
        let generatedRoot = temporaryDirectory(prefix: "SumiNormalTabPreparedBundles")
        let preparedBundle = generatedRoot
            .appendingPathComponent(SumiProtectionBundleProfile.adblock, isDirectory: true)
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(at: preparedBundle)
        let manifestStore = AdblockUpdateManifestStore(
            rootDirectory: temporaryDirectory(prefix: "SumiNormalTabAdblockManifest")
        )
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: registry,
            preparedBundleResourceURL: temporaryDirectory(prefix: "SumiNormalTabEmptyResources"),
            preparedBundleRemoteRootURL: temporaryDirectory(prefix: "SumiNormalTabEmptyRemote"),
            preparedBundleGeneratedRootURL: generatedRoot,
            ruleListStoreFactory: { settings, isEnabled in
                AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler(),
                    embeddedBundleURLProvider: { nil }
                )
            }
        )
        let coordinator = SumiProtectionCoordinator(
            settings: protectionSettings,
            adBlockingModule: adBlockingModule,
            moduleRegistry: registry
        )
        return (adBlockingModule, coordinator)
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

    @discardableResult
    private func waitForAssets(
        on controller: SumiNormalTabUserContentControlling,
        timeout: TimeInterval = 5,
        where predicate: @escaping (SumiNormalTabContentBlockingAssetSummary) -> Bool
    ) async throws -> SumiNormalTabContentBlockingAssetSummary {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let summary = controller.contentBlockingAssetSummary
            if summary.isInstalled, predicate(summary) {
                return summary
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for normal-tab content-blocking assets: \(controller.contentBlockingAssetSummary)")
        return controller.contentBlockingAssetSummary
    }

    @discardableResult
    private func waitForAssets(
        on tab: Tab,
        timeout: TimeInterval = 5,
        where predicate: @escaping (SumiNormalTabContentBlockingAssetSummary) -> Bool
    ) async throws -> SumiNormalTabContentBlockingAssetSummary {
        let deadline = Date().addingTimeInterval(timeout)
        var latestSummary: SumiNormalTabContentBlockingAssetSummary?
        while Date() < deadline {
            guard let controller = tab.existingWebView?
                .configuration
                .userContentController
                .sumiNormalTabUserContentController
            else {
                try await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            let summary = controller.contentBlockingAssetSummary
            latestSummary = summary
            if summary.isInstalled, predicate(summary) {
                return summary
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for current-tab content-blocking assets: \(latestSummary.map { String(describing: $0) } ?? "nil")")
        return latestSummary ?? SumiNormalTabContentBlockingAssetSummary(
            isInstalled: false,
            globalRuleListCount: 0,
            updateRuleCount: 0,
            isContentBlockingFeatureEnabled: false,
            globalRuleListIdentifiers: [],
            lookupSucceededIdentifiers: [],
            lookupFailedIdentifiers: [],
            addedToUserContentControllerIdentifiers: [],
            ruleListLookupDuration: nil,
            tabAttachmentDuration: nil
        )
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func temporaryDirectory(prefix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private static func makeInMemoryExtensionContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
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
