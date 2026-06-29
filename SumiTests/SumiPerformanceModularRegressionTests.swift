import Foundation
import SwiftData
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
        let userscriptsProbe = UserscriptsRuntimeProbe()
        let extensionsProbe = ExtensionsRuntimeProbe()
        let userscriptsModule = makeUserscriptsModule(
            registry: registry,
            probe: userscriptsProbe
        )
        let extensionsModule = try makeExtensionsModule(
            registry: registry,
            probe: extensionsProbe
        )

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            userscriptsModule: userscriptsModule
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertEqual(userscriptsProbe.managerCount, 0)
        XCTAssertEqual(userscriptsProbe.storeCount, 0)
        XCTAssertEqual(userscriptsProbe.injectorCount, 0)
        XCTAssertEqual(extensionsProbe.managerCount, 0)
        XCTAssertFalse(userscriptsModule.hasLoadedRuntime)
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
        let userscriptsProbe = UserscriptsRuntimeProbe()
        let extensionsProbe = ExtensionsRuntimeProbe()
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: try makeExtensionsModule(
                registry: registry,
                probe: extensionsProbe
            ),
            userscriptsModule: makeUserscriptsModule(
                registry: registry,
                probe: userscriptsProbe
            )
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/prompt-20-default-normal-tab",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let webView = try XCTUnwrap(tab.existingWebView)
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserScriptsProvider)
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertEqual(controller.contentBlockingAssetSummary.updateRuleCount, 0)
        XCTAssertFalse(controller.contentBlockingAssetSummary.isContentBlockingFeatureEnabled)
        XCTAssertTrue(controller.contentBlockingAssetSummary.addedToUserContentControllerIdentifiers.isEmpty)
        XCTAssertNil(controller.contentBlockingAssetSummary.tabAttachmentDuration)
        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("__sumiTabSuspension"))
        assertNoOptionalModuleScriptsOrHandlers(in: webView.configuration.userContentController)
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertFalse(browserManager.adBlockingModule.hasLoadedRuntime)
        XCTAssertFalse(browserManager.adBlockingModule.isEnabled)
        XCTAssertFalse(browserManager.adBlockingModule.isPreparedBundleRuntimeEnabled)

        let suspensionScript = try XCTUnwrap(
            tab.normalTabCoreUserScripts().first { $0.source.contains("__sumiTabSuspension") }
        )
        XCTAssertTrue(suspensionScript.forMainFrameOnly)
        XCTAssertEqual(userscriptsProbe.managerCount, 0)
        XCTAssertEqual(userscriptsProbe.storeCount, 0)
        XCTAssertEqual(userscriptsProbe.injectorCount, 0)
        XCTAssertEqual(extensionsProbe.managerCount, 0)
    }

    func testEnabledModulesRemainSeparated() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )

        registry.enable(.userScripts)
        XCTAssertTrue(registry.isEnabled(.userScripts))
        XCTAssertFalse(registry.isEnabled(.extensions))

        registry.disable(.userScripts)
        registry.enable(.extensions)
        XCTAssertTrue(registry.isEnabled(.extensions))
        XCTAssertFalse(registry.isEnabled(.userScripts))
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
            assertNoOptionalModuleScriptsOrHandlers(in: configuration.userContentController)
        }

        let sourceConfiguration = WKWebViewConfiguration()
        for marker in [
            "__sumiTabSuspension",
            SumiTransientChromeInteractionShieldUserScript.sourceMarker,
            "sumiLinkInteraction_",
            "SUMI_USER_SCRIPT_RUNTIME",
            "sumiGM_",
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

    func testDisabledUserscriptsModuleReturnsNoRuntimeContributions() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = UserscriptsRuntimeProbe()
        let module = makeUserscriptsModule(registry: registry, probe: probe)
        let tab = Tab(name: "Userscripts Disabled")

        let contributions = module.normalTabUserScripts(
            for: URL(string: "https://example.com/userscripts-disabled")!,
            webViewId: tab.id,
            profileId: nil,
            isEphemeral: false
        )

        XCTAssertTrue(contributions.isEmpty)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertEqual(probe.injectorCount, 0)
        XCTAssertTrue(tab.normalTabCoreUserScripts().contains { $0.source.contains("__sumiTabSuspension") })
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
        module.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: "Prompt20.disabled"
        )
        XCTAssertNil(configuration.webExtensionController)
        XCTAssertEqual(probe.managerCount, 0)
    }

    private func makeUserscriptsModule(
        registry: SumiModuleRegistry,
        probe: UserscriptsRuntimeProbe
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
                                    "SumiPrompt20Userscripts-\(UUID().uuidString)",
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

    private func makeExtensionsModule(
        registry: SumiModuleRegistry,
        probe: ExtensionsRuntimeProbe
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let initialProfile = Profile(name: "Prompt 20 Extensions")
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { initialProfile },
            managerFactory: { context, initialProfile, browserConfiguration, moduleRegistry in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration,
                    moduleRegistry: moduleRegistry
                )
            }
        )
    }

    private func assertNoOptionalModuleScriptsOrHandlers(
        in userContentController: WKUserContentController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let wkSources = userContentController.userScripts.map(\.source).joined(separator: "\n")
        let provider = userContentController.sumiNormalTabUserScriptsProvider
        let providerSources = provider?.userScripts.map(\.source).joined(separator: "\n") ?? ""
        let messageNames = provider?.userScripts.flatMap(\.messageNames).joined(separator: "\n") ?? ""
        let combined = [wkSources, providerSources, messageNames].joined(separator: "\n")

        for marker in [
            UserScriptInjector.userScriptMarker,
            "SUMI_USER_SCRIPT_RUNTIME",
            "data-sumi-userscript",
            "sumiGM_",
        ] {
            XCTAssertFalse(combined.contains(marker), marker, file: file, line: line)
        }
    }
}

private final class UserscriptsRuntimeProbe {
    var managerCount = 0
    var storeCount = 0
    var injectorCount = 0
}

private final class ExtensionsRuntimeProbe {
    var managerCount = 0
}
