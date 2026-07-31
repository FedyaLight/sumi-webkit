import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiPerformanceModularRegressionTests: XCTestCase {
    func testCleanInstallDefaultsAndIndependentModuleToggles() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)
        let settings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.memoryMode, .balanced)
        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 2 * 60 * 60)
        for moduleID in SumiModuleID.allCases {
            XCTAssertFalse(registry.isEnabled(moduleID), "\(moduleID.rawValue) should default to disabled")
            XCTAssertNil(harness.defaults.object(forKey: store.key(for: moduleID)))
        }

        for enabledModule in SumiModuleID.allCases {
            let scopedHarness = TestDefaultsHarness()
            defer { scopedHarness.reset() }
            let scopedRegistry = SumiModuleRegistry(
                settingsStore: SumiModuleSettingsStore(userDefaults: scopedHarness.defaults)
            )

            scopedRegistry.enable(enabledModule)

            for moduleID in SumiModuleID.allCases {
                XCTAssertEqual(
                    scopedRegistry.isEnabled(moduleID),
                    moduleID == enabledModule,
                    "Toggling \(enabledModule.rawValue) changed \(moduleID.rawValue)"
                )
            }

            scopedRegistry.disable(enabledModule)
            for moduleID in SumiModuleID.allCases {
                XCTAssertFalse(scopedRegistry.isEnabled(moduleID))
            }
        }
    }

    func testPrompt22MemorySaverRegressionGates() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        harness.defaults.set("lightweight", forKey: "settings.memoryMode")
        XCTAssertEqual(SumiSettingsService(userDefaults: harness.defaults).memoryMode, .maximum)
        harness.defaults.set("performance", forKey: "settings.memoryMode")
        XCTAssertEqual(SumiSettingsService(userDefaults: harness.defaults).memoryMode, .moderate)
        harness.defaults.set("unknown", forKey: "settings.memoryMode")
        XCTAssertEqual(SumiSettingsService(userDefaults: harness.defaults).memoryMode, .balanced)

        XCTAssertEqual(TabSuspensionPolicy(memoryMode: .moderate).proactiveDeactivationDelay, 6 * 60 * 60)
        XCTAssertEqual(TabSuspensionPolicy(memoryMode: .balanced).proactiveDeactivationDelay, 4 * 60 * 60)
        XCTAssertEqual(TabSuspensionPolicy(memoryMode: .maximum).proactiveDeactivationDelay, 2 * 60 * 60)
        XCTAssertEqual(
            TabSuspensionPolicy(memoryMode: .custom, customDeactivationDelay: 20 * 60).proactiveDeactivationDelay,
            20 * 60
        )
        XCTAssertEqual(SumiMemorySaverCustomDelay.clamped(30), 60)
        XCTAssertEqual(SumiMemorySaverCustomDelay.clamped(5 * 60), 5 * 60)
        XCTAssertEqual(SumiMemorySaverCustomDelay.clamped(48 * 60 * 60), 2 * 60 * 60)
    }

    func testBrowserManagerStartupAndSettingsSurfacesDoNotConstructDisabledRuntimes() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let extensionsProbe = ExtensionsRuntimeProbe()
        let extensionsModule = try makeExtensionsModule(
            registry: registry,
            probe: extensionsProbe
        )

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertEqual(extensionsProbe.managerCount, 0)
        XCTAssertFalse(extensionsModule.hasLoadedRuntime)
        XCTAssertFalse(browserManager.optionalModules.boosts.hasLoadedRuntime)
        // W4/R9: disabled modules must not receive attach(runtime:) at wiring time.
        XCTAssertFalse(extensionsModule.hasAttachedRuntime)
        XCTAssertFalse(browserManager.optionalModules.boosts.hasAttachedRuntime)
        XCTAssertFalse(browserManager.optionalModules.liveFolders.hasAttachedRuntime)
        XCTAssertFalse(browserManager.liveFolderManager.hasAttachedRuntime)
    }

    func testEnablingOptionalModuleAfterStartupAttachesRuntime() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let extensionsProbe = ExtensionsRuntimeProbe()
        let extensionsModule = try makeExtensionsModule(
            registry: registry,
            probe: extensionsProbe
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule
        )

        XCTAssertFalse(browserManager.optionalModules.boosts.hasAttachedRuntime)
        XCTAssertFalse(extensionsModule.hasAttachedRuntime)

        browserManager.optionalModules.boosts.setEnabled(true)
        XCTAssertTrue(browserManager.optionalModules.boosts.hasAttachedRuntime)

        extensionsModule.setEnabled(true)
        XCTAssertTrue(extensionsModule.hasAttachedRuntime)
        XCTAssertTrue(extensionsModule.hasLoadedRuntime)
        XCTAssertEqual(extensionsProbe.managerCount, 1)

        browserManager.optionalModules.boosts.setEnabled(false)
        XCTAssertFalse(browserManager.optionalModules.boosts.hasAttachedRuntime)

        extensionsModule.setEnabled(false)
        XCTAssertFalse(extensionsModule.hasAttachedRuntime)
        XCTAssertFalse(extensionsModule.hasLoadedRuntime)
    }

    func testYouTubeFaviconSelectionPrefersSharpDocumentCandidateOverTinyShortcutIcon() throws {
        let documentURL = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=J8O9LLpJNrg"))
        let tinyURL = try XCTUnwrap(URL(string: "https://www.youtube.com/favicon.ico"))
        let sharpURL = try XCTUnwrap(URL(string: "https://www.youtube.com/s/desktop/test/img/favicon_48x48.png"))
        let tiny = SumiFaviconCandidate(
            pageURL: documentURL,
            iconURL: tinyURL,
            sourceKind: .documentLink,
            relTokens: ["shortcut", "icon"],
            declaredSizes: [SumiFaviconDeclaredSize(width: 16, height: 16)],
            declaredType: "image/x-icon",
            partition: .regular(nil)
        )
        let sharp = SumiFaviconCandidate(
            pageURL: documentURL,
            iconURL: sharpURL,
            sourceKind: .documentLink,
            relTokens: ["icon"],
            declaredSizes: [SumiFaviconDeclaredSize(width: 48, height: 48)],
            declaredType: "image/png",
            partition: .regular(nil)
        )

        let selected = SumiFaviconCandidateSelector.bestCandidate(
            [tiny, sharp],
            for: .pinnedLauncher,
            backingScale: 2
        )

        XCTAssertEqual(selected?.iconURL, sharpURL)
    }

    func testDefaultNormalTabAttachesOnlyCoreRuntimeAndNoOptionalModuleAssets() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let extensionsProbe = ExtensionsRuntimeProbe()
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: try makeExtensionsModule(
                registry: registry,
                probe: extensionsProbe
            )
        )
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/prompt-20-default-normal-tab",
            in: browserManager.spaceStateOwner.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let webView = try XCTUnwrap(tab.resolvedCurrentWebView())
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserScriptsProvider)
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertEqual(controller.contentBlockingAssetSummary.updateRuleCount, 0)
        XCTAssertFalse(controller.contentBlockingAssetSummary.isContentBlockingFeatureEnabled)
        XCTAssertTrue(controller.contentBlockingAssetSummary.addedToUserContentControllerIdentifiers.isEmpty)
        XCTAssertNil(controller.contentBlockingAssetSummary.tabAttachmentDuration)
        XCTAssertTrue(sources.contains("sumiLinkInteraction"))
        XCTAssertTrue(sources.contains("sumiTabSuspension"))
        XCTAssertTrue(sources.contains("__sumiTabSuspension"))
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertFalse(browserManager.adBlockingModule.hasLoadedRuntime)
        XCTAssertFalse(browserManager.optionalModules.boosts.hasLoadedRuntime)
        XCTAssertFalse(browserManager.adBlockingModule.isEnabled)
        XCTAssertFalse(browserManager.adBlockingModule.isPreparedBundleRuntimeEnabled)

        let suspensionScript = try XCTUnwrap(
            tab.normalTabCoreUserScripts().first { $0.source.contains("__sumiTabSuspension") }
        )
        XCTAssertTrue(suspensionScript.forMainFrameOnly)
        XCTAssertEqual(extensionsProbe.managerCount, 0)
    }

    func testEnabledModulesRemainSeparated() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )

        registry.enable(.extensions)
        XCTAssertTrue(registry.isEnabled(.extensions))
        XCTAssertFalse(registry.isEnabled(.boosts))

        registry.disable(.extensions)
        registry.enable(.boosts)
        XCTAssertTrue(registry.isEnabled(.boosts))
        XCTAssertFalse(registry.isEnabled(.extensions))
    }

    func testAuxiliaryConfigurationsStayLightweight() {
        let browserConfiguration = BrowserConfiguration()
        let surfaces = BrowserConfigurationAuxiliarySurface.allCases

        for surface in surfaces {
            let configuration = browserConfiguration.auxiliaryWebViewConfiguration(surface: surface)

            XCTAssertNil(configuration.userContentController.sumiNormalTabUserContentController, surface.rawValue)
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserScriptsProvider, surface.rawValue)
            XCTAssertTrue(configuration.userContentController.userScripts.isEmpty, surface.rawValue)
            XCTAssertNil(configuration.webExtensionController, surface.rawValue)
        }

        let sourceConfiguration = WKWebViewConfiguration()
        for marker in [
            "__sumiTabSuspension",
            SumiTransientChromeInteractionShieldUserScript.sourceMarker,
            "sumiLinkInteraction",
        ] {
            sourceConfiguration.userContentController.addUserScript(
                WKUserScript(
                    source: "/* \(marker) */",
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }
        let filteredConfiguration = browserConfiguration.auxiliaryWebViewConfiguration(
            from: sourceConfiguration,
            surface: .extensionOptions,
            additionalUserScripts: sourceConfiguration.userContentController.userScripts
        )
        XCTAssertTrue(filteredConfiguration.userContentController.userScripts.isEmpty)
    }

    func testDisabledExtensionsModuleDoesNotPrepareRuntimeController() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ExtensionsRuntimeProbe()
        let module = try makeExtensionsModule(registry: registry, probe: probe)
        let configuration = WKWebViewConfiguration()

        XCTAssertTrue(module.normalTabUserScripts().isEmpty)
        module.prepareWebViewConfigForExtensionRuntime(
            configuration,
            reason: "Prompt20.disabled"
        )
        XCTAssertNil(configuration.webExtensionController)
        XCTAssertEqual(probe.managerCount, 0)
    }

    private func makeExtensionsModule(
        registry: SumiModuleRegistry,
        probe: ExtensionsRuntimeProbe
    ) throws -> SumiExtensionsModule {
        let container = try SumiDatabase.inMemory()
        let initialProfile = Profile(name: "Prompt 20 Extensions")
        return SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { initialProfile },
            managerFactory: { context, initialProfile, browserConfiguration, moduleRegistry in
                probe.managerCount += 1
                return ExtensionManager(
            database: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration,
                    moduleRegistry: moduleRegistry
                )
            }
        )
    }
}

private final class ExtensionsRuntimeProbe {
    var managerCount = 0
}
