import Combine
import CryptoKit
import Foundation
import SumiDomain
import WebKit
import XCTest

@testable import Sumi

@MainActor
extension BrowserConfigurationNormalTabTests {
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
            context: container
        )

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: module
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertFalse(registry.isEnabled(.extensions))
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertTrue(browserManager.optionalModules.extensions.surfaceStore.installedExtensions.isEmpty)
    }

    func testBrowserManagerStartupWithBoostsDisabledDoesNotInitializeBoostsRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabBoostsRuntimeProbe()
        let module = makeProbeBoostsModule(
            registry: registry,
            probe: probe
        )

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            boostsModule: module
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertFalse(registry.isEnabled(.boosts))
        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
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
            context: container
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: module
        )
        markIsolatedTabManagerReady(browserManager)
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/extensions-disabled",
            in: browserManager.spaceStateOwner.currentSpace,
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

        XCTAssertTrue(sources.contains("sumiLinkInteraction"))
        XCTAssertTrue(sources.contains("sumiTabSuspension"))
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testTabNormalWebViewCreationWithBoostsDisabledDoesNotInitializeBoostsRuntime() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabBoostsRuntimeProbe()
        let module = makeProbeBoostsModule(
            registry: registry,
            probe: probe
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            boostsModule: module
        )
        markIsolatedTabManagerReady(browserManager)
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/boosts-disabled",
            in: browserManager.spaceStateOwner.currentSpace,
            activate: false
        )

        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.boostsDisabled"
        )
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(controller.normalTabUserScriptsProvider)
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertTrue(sources.contains("sumiLinkInteraction"))
        XCTAssertTrue(sources.contains("sumiTabSuspension"))
        XCTAssertFalse(sources.contains(SumiBoostCSSBuilder.styleAttribute))
        XCTAssertFalse(sources.contains(SumiBoostCSSBuilder.filterStyleAttribute))
        XCTAssertEqual(probe.storeCount, 0)
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

        XCTAssertNotIdentical(first.userContentController, second.userContentController)
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
        XCTAssertIdentical(configuration.websiteDataStore, profile.dataStore)
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
        XCTAssertIdentical(firstStore, secondStore)
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
        XCTAssertNotIdentical(firstStore, secondStore)
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
        XCTAssertNotIdentical(persistentStore, firstEphemeralStore)
        XCTAssertNotIdentical(firstEphemeralStore, secondEphemeralStore)
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
        XCTAssertIdentical(normalStore, auxiliaryStore)

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
        XCTAssertNotIdentical(normalStore, auxiliaryStore)

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
            XCTAssertIdentical(configuration.websiteDataStore, profile.dataStore)
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
            "__sumiDocumentSuspensionSensor",
            "__sumiSubframePictureInPicture",
            SumiTransientChromeInteractionShieldUserScript.sourceMarker,
            "sumiFavicons",
            "sumiLinkInteraction",
            "sumiTabSuspension",
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
            "__sumiDocumentSuspensionSensor",
            "__sumiSubframePictureInPicture",
            SumiTransientChromeInteractionShieldUserScript.sourceMarker,
            "sumiFavicons",
            "sumiLinkInteraction",
            "sumiTabSuspension",
        ] {
            XCTAssertFalse(sources.contains(blockedMarker), blockedMarker)
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

        XCTAssertTrue(sources.contains("sumiLinkInteraction"))
        XCTAssertTrue(sources.contains("sumiTabSuspension"))
        XCTAssertTrue(sources.contains("__sumiTabSuspension"))

        let linkInteractionScript = try XCTUnwrap(
            provider.userScripts.first { $0.source.contains("sumiLinkInteraction") }
        )
        let contextMenuScript = try XCTUnwrap(
            provider.userScripts.first { $0.source.contains("sumiWebPageContextMenu") }
        )
        let notificationScript = try XCTUnwrap(
            provider.userScripts.first { $0.source.contains("sumiWebNotifications") }
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

    func testTabSuspensionSeparatesPageAPIFromIsolatedSensors() throws {
        let tab = Tab(name: "Bridge")
        let scripts = tab.normalTabCoreUserScripts()
        let bridgeScript = try XCTUnwrap(
            scripts.first { script in
                script.source.contains("__sumiTabSuspension")
            }
        )
        let documentSensor = try XCTUnwrap(
            scripts.first { script in
                script.source.contains("__sumiDocumentSuspensionSensor")
            }
        )
        let subframeSensor = try XCTUnwrap(
            scripts.first { script in
                script.source.contains("__sumiSubframePictureInPictureBootstrap")
            }
        )

        XCTAssertTrue(bridgeScript.source.contains("sumiTabSuspension"))
        XCTAssertTrue(bridgeScript.source.contains("let pageAllowsSuspension = true"))
        XCTAssertTrue(
            bridgeScript.source.contains("pageAllowsSuspension = canBeSuspended")
        )
        XCTAssertTrue(bridgeScript.source.contains("reply.catch(() => {})"))
        XCTAssertTrue(bridgeScript.forMainFrameOnly)
        XCTAssertTrue(bridgeScript.requiresRunInPageContentWorld)
        XCTAssertFalse(bridgeScript.source.contains("documentLeaseToken"))
        XCTAssertFalse(bridgeScript.source.contains("activateCommittedDocument"))

        XCTAssertTrue(documentSensor.forMainFrameOnly)
        XCTAssertFalse(documentSensor.requiresRunInPageContentWorld)
        XCTAssertTrue(documentSensor.source.contains("documentLeaseToken"))
        XCTAssertTrue(documentSensor.source.contains("webkitpresentationmodechanged"))

        XCTAssertFalse(subframeSensor.forMainFrameOnly)
        XCTAssertFalse(subframeSensor.requiresRunInPageContentWorld)
    }

}
