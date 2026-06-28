import CryptoKit
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
        XCTAssertEqual(
            configuration.preferences.value(forKey: "developerExtrasEnabled") as? Bool,
            RuntimeDiagnostics.isDeveloperInspectionEnabled
        )

        await controller.waitForContentBlockingAssetsInstalled()

        let contentBlockingSummary = controller.contentBlockingAssetSummary
        XCTAssertTrue(contentBlockingSummary.isInstalled)
        XCTAssertFalse(controller.wkUserContentController.userScripts.isEmpty)
        XCTAssertEqual(contentBlockingSummary.globalRuleListCount, 0)
    }

    func testTabNormalWebViewCreationInstallsProtectionCoordinatorPreparedBundleRules() async throws {
        let fixture = try makePreparedProtectionBundleFixture()
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let settings = SumiProtectionSettings(userDefaults: harness.defaults)
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: fixture.manifestStoreRoot)
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: registry,
            preparedBundleResourceURL: fixture.resourceRoot,
            preparedBundleRemoteRootURL: fixture.remoteRoot,
            preparedBundleGeneratedRootURL: nil,
            ruleListStoreFactory: { isEnabled in
                AdblockWebKitRuleListStore(
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    embeddedBundleURLProvider: { fixture.bundleURL }
                )
            }
        )
        let protectionCoordinator = SumiProtectionCoordinator(
            settings: settings,
            adBlockingModule: adBlockingModule,
            bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore(userDefaults: harness.defaults)
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(container: try Self.makeInMemoryStartupContainer()),
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator
        )
        await waitForStartupProtectionRestore(on: browserManager)

        settings.setLevel(.protection)
        settings.setAppliedLevel(.protection)
        _ = try await protectionCoordinator.restoreAppliedLevelForStartup()

        let profile = try XCTUnwrap(browserManager.currentProfile)
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/protection",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let decision = protectionCoordinator.normalTabDecision(for: tab.url, profileId: profile.id)
        let expectedIdentifiers = Set(fixture.ruleListIdentifiers)

        XCTAssertEqual(Set(decision.plan.expectedRuleListIdentifiers), expectedIdentifiers)
        XCTAssertNotNil(decision.contentBlockingService)

        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.protectionPreparedBundleRules"
        )
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let summary = controller.contentBlockingAssetSummary

        XCTAssertTrue(summary.isInstalled)
        XCTAssertTrue(summary.isContentBlockingFeatureEnabled)
        XCTAssertEqual(summary.globalRuleListCount, expectedIdentifiers.count)
        XCTAssertEqual(summary.updateRuleCount, expectedIdentifiers.count)
        XCTAssertEqual(Set(summary.globalRuleListIdentifiers), expectedIdentifiers)
        XCTAssertEqual(Set(summary.lookupSucceededIdentifiers), expectedIdentifiers)
        XCTAssertEqual(Set(summary.addedToUserContentControllerIdentifiers), expectedIdentifiers)
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
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
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
            surface: .glance
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
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
        ]

        configurations.forEach { configuration in
            assertNoTabSuspensionBridge(in: configuration)
        }
    }

    func testAuxiliaryConfigurationsUsePlainLightweightControllers() {
        let browserConfiguration = BrowserConfiguration()
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
        ]

        for configuration in configurations {
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserContentController)
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserScriptsProvider)
            XCTAssertTrue(configuration.userContentController.userScripts.isEmpty)
            XCTAssertNil(configuration.webExtensionController)
        }
    }

    func testFaviconV2DoesNotDeclareAuxiliaryDownloadSurface() throws {
        let browserConfigSource = try Self.source(named: "Sumi/Models/BrowserConfig/BrowserConfig.swift")
        let fetchSource = try Self.source(named: "Sumi/Favicons/V2/SumiFaviconFetchScheduler.swift")

        XCTAssertFalse(browserConfigSource.contains("case faviconDownload"))
        XCTAssertFalse(browserConfigSource.contains("Sumi Web Content (Favicon)"))
        XCTAssertFalse(Self.fileExists("Sumi/Favicons/DDG/Model/FaviconDownloader.swift"))
        XCTAssertTrue(fetchSource.contains("case sessionProfileAware"))
        XCTAssertTrue(fetchSource.contains("case publicRootFallback"))
        XCTAssertTrue(fetchSource.contains("URLSession(configuration: .ephemeral)"))
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
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
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
            "__sumiFaviconTransportInstalled",
            "__sumiTabSuspension",
            SumiTransientChromeInteractionShieldUserScript.sourceMarker,
            "SUMI_USER_SCRIPT_RUNTIME",
            UserScriptInjector.userScriptMarker,
            "sumiFavicons",
            "sumiGM_",
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
            "__sumiFaviconTransportInstalled",
            "__sumiTabSuspension",
            SumiTransientChromeInteractionShieldUserScript.sourceMarker,
            "SUMI_USER_SCRIPT_RUNTIME",
            UserScriptInjector.userScriptMarker,
            "sumiFavicons",
            "sumiGM_",
            "sumiLinkInteraction_",
            "sumiTabSuspension_",
        ] {
            XCTAssertFalse(sources.contains(blockedMarker), blockedMarker)
        }
    }

    func testAuxiliaryAndFaviconPathsDoNotAccessContentBlockingRuntime() throws {
        for relativePath in [
            "Sumi/Favicons/V2/SumiFaviconFetchScheduler.swift",
            "Sumi/Favicons/V2/SumiFaviconService.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("contentBlockingServiceIfEnabled"), relativePath)
            XCTAssertFalse(source.contains("SumiContentBlockingService"), relativePath)
        }
    }

    func testAuxiliaryAndFaviconPathsDoNotAccessUserscriptsRuntime() throws {
        for relativePath in [
            "Sumi/Favicons/V2/SumiFaviconFetchScheduler.swift",
            "Sumi/Favicons/V2/SumiFaviconService.swift",
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
            "Sumi/Favicons/V2/SumiFaviconFetchScheduler.swift",
            "Sumi/Favicons/V2/SumiFaviconService.swift",
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
        let faviconSource = try Self.source(named: "Sumi/Favicons/V2/SumiFaviconFetchScheduler.swift")
        XCTAssertFalse(Self.fileExists("Sumi/Favicons/DDG/Model/FaviconDownloader.swift"))
        XCTAssertFalse(faviconSource.contains("WKWebViewConfiguration()"))
        XCTAssertFalse(faviconSource.contains("normalTabWebViewConfiguration("))

        for relativePath in [
            "Sumi/Managers/ExtensionManager/ExtensionOptionsWindowPresenter.swift",
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

    func testCoordinatorDelegatesNormalWebViewCreationWithoutFallbackToGlance() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinatorSourceURL = repoRoot
            .appendingPathComponent("Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift")
        let ownerSourceURL = repoRoot
            .appendingPathComponent("Sumi/Managers/WebViewCoordinator/WebViewAssignmentRebuildOwner.swift")
        let coordinatorSource = try String(contentsOf: coordinatorSourceURL, encoding: .utf8)
        let ownerSource = try String(contentsOf: ownerSourceURL, encoding: .utf8)
        let combinedSource = coordinatorSource + "\n" + ownerSource

        XCTAssertFalse(combinedSource.contains("createWebViewInternal"))
        XCTAssertFalse(combinedSource.contains("normalTabWebViewConfiguration"))
        XCTAssertFalse(combinedSource.contains("auxiliaryWebViewConfiguration"))
        XCTAssertFalse(combinedSource.contains("surface: .glance"))
        XCTAssertFalse(combinedSource.contains("FocusableWKWebView(frame: .zero"))
        XCTAssertFalse(coordinatorSource.contains("tab.ensureWebView()"))
        XCTAssertFalse(coordinatorSource.contains("tab.makeNormalTabWebView"))
        XCTAssertTrue(ownerSource.contains("tab.ensureWebView()"))
        XCTAssertTrue(ownerSource.contains("tab.makeNormalTabWebView"))
    }

    func testBrowserConfigurationDoesNotExposeLegacyCompatibilityAliases() throws {
        let source = try Self.source(named: "Sumi/Models/BrowserConfig/BrowserConfig.swift")

        XCTAssertFalse(source.contains("cacheOptimizedWebViewConfiguration"))
        XCTAssertFalse(source.contains("webViewConfiguration(for:"))
    }

    func testBrowserManagerDoesNotConstructSumiScriptsManagerAtStartup() throws {
        let browserManagerSource = try Self.source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")
        let runtimeWiringSource = try Self.source(
            named: "Sumi/Managers/BrowserManager/BrowserManagerRuntimeWiring.swift"
        )

        XCTAssertTrue(browserManagerSource.contains("let userscriptsModule: SumiUserscriptsModule"))
        XCTAssertTrue(
            runtimeWiringSource.contains(
                "browserManager.userscriptsModule.attach(browserManager: browserManager)"
            )
        )
        XCTAssertFalse(browserManagerSource.contains("let sumiScriptsManager"))
        XCTAssertFalse(browserManagerSource.contains("self.sumiScriptsManager"))
        XCTAssertFalse(browserManagerSource.contains("SumiScriptsManager("))
    }

    func testBrowserManagerDoesNotConstructExtensionManagerAtStartup() throws {
        let browserManagerSource = try Self.source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")
        let runtimeWiringSource = try Self.source(
            named: "Sumi/Managers/BrowserManager/BrowserManagerRuntimeWiring.swift"
        )

        XCTAssertTrue(browserManagerSource.contains("let extensionsModule: SumiExtensionsModule"))
        XCTAssertTrue(
            runtimeWiringSource.contains(
                "browserManager.extensionsModule.attach(browserManager: browserManager)"
            )
        )
        XCTAssertFalse(browserManagerSource.contains("let extensionManager"))
        XCTAssertFalse(browserManagerSource.contains("self.extensionManager"))
        XCTAssertFalse(browserManagerSource.contains("ExtensionManager("))
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

    private static func fileExists(_ relativePath: String) -> Bool {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(relativePath).path)
    }

    private func temporaryDirectory(prefix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makePreparedProtectionBundleFixture() throws -> (
        resourceRoot: URL,
        remoteRoot: URL,
        bundleURL: URL,
        manifestStoreRoot: URL,
        ruleListIdentifiers: [String]
    ) {
        let root = temporaryDirectory(prefix: "SumiNormalTabProtectionBundle")
        let resourceRoot = root.appendingPathComponent("Resources", isDirectory: true)
        let remoteRoot = root.appendingPathComponent("Remote", isDirectory: true)
        let manifestStoreRoot = root.appendingPathComponent("ManifestStore", isDirectory: true)
        let bundleURL = resourceRoot
            .appendingPathComponent("SumiAdblockBundles", isDirectory: true)
            .appendingPathComponent(SumiProtectionBundleProfile.adblock, isDirectory: true)
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifestStoreRoot, withIntermediateDirectories: true)

        let shard = try writePreparedBundleShard(
            bundleURL: bundleURL,
            group: .trackingNetwork,
            relativePath: "tracking/tracking-0001.json"
        )
        let manifest = makePreparedBundleManifest(shards: [shard.shard])
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(
            to: bundleURL.appendingPathComponent(SumiAdblockNativeRuleBundle.manifestFileName),
            options: [.atomic]
        )

        return (
            resourceRoot: resourceRoot,
            remoteRoot: remoteRoot,
            bundleURL: bundleURL,
            manifestStoreRoot: manifestStoreRoot,
            ruleListIdentifiers: [shard.identifier]
        )
    }

    private func writePreparedBundleShard(
        bundleURL: URL,
        group: SumiProtectionGroupKind,
        relativePath: String
    ) throws -> (identifier: String, shard: SumiAdblockNativeRuleBundleManifest.Shard) {
        let shardURL = bundleURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: shardURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Self.validPreparedBundleRuleListData(group: group)
        try data.write(to: shardURL, options: [.atomic])
        let identifier = "SumiTestProtection\(group.rawValue)\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"

        return (
            identifier: identifier,
            shard: SumiAdblockNativeRuleBundleManifest.Shard(
                kind: "network",
                group: group.rawValue,
                logicalGroup: group.rawValue,
                relativePath: relativePath,
                hash: Self.sha256Hex(data),
                byteSize: data.count,
                ruleCount: 1,
                webKitIdentifier: identifier
            )
        )
    }

    private func makePreparedBundleManifest(
        shards: [SumiAdblockNativeRuleBundleManifest.Shard]
    ) -> SumiAdblockNativeRuleBundleManifest {
        SumiAdblockNativeRuleBundleManifest(
            schemaVersion: 1,
            bundleId: "sumi-test-protection-\(UUID().uuidString)",
            generationId: "generation-\(UUID().uuidString)",
            profileId: SumiProtectionBundleProfile.adblock,
            compiler: .init(name: "SumiTests", version: "1"),
            nativeCSSSafetyPolicyVersion: SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion,
            generatedDate: "2026-06-26T00:00:00Z",
            lists: [],
            profileLevelMapping: nil,
            groups: nil,
            shards: shards,
            diagnosticsSummary: .init(
                inputRuleCount: shards.count,
                finalRuleCount: shards.count,
                finalShardCount: shards.count,
                networkRuleCount: shards.count,
                nativeCSSRuleCount: 0,
                unsafeCSSFilteredCount: 0,
                warnings: []
            ),
            unsafeCSSFilteredCount: 0,
            deduplication: .init(
                inputRawRuleCount: shards.count,
                rawDuplicateCountRemoved: 0,
                nativeJSONDuplicateCountRemoved: 0,
                skippedDedupeCount: 0,
                skippedDedupeReasons: [:],
                finalRuleCount: shards.count,
                finalShardCount: shards.count
            )
        )
    }

    private func waitForStartupProtectionRestore(on browserManager: BrowserManager) async {
        for _ in 0..<100 {
            if browserManager.hasFinishedStartupProtectionRestore { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for initial startup protection restore")
    }

    private static func makeInMemoryExtensionContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private static func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private static func validPreparedBundleRuleListData(group: SumiProtectionGroupKind) -> Data {
        Data(
            """
            [
              {
                "trigger": {
                  "url-filter": ".*sumi-\(group.rawValue)-blocked\\\\.example/.*"
                },
                "action": {
                  "type": "block"
                }
              }
            ]
            """.utf8
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
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
