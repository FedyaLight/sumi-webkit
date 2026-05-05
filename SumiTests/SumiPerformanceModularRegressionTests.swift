import BrowserServicesKit
import SwiftData
import UserScript
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
        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 4 * 60 * 60)
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

    func testPrompt22MemorySaverRegressionGates() throws {
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
        XCTAssertEqual(SumiMemorySaverCustomDelay.clamped(5 * 60), 15 * 60)
        XCTAssertEqual(SumiMemorySaverCustomDelay.clamped(48 * 60 * 60), 24 * 60 * 60)

        let settingsSource = try Self.source(named: "Sumi/Components/Settings/Tabs/Performance.swift")
        XCTAssertTrue(settingsSource.contains("title: \"Memory Saver\""))
        XCTAssertTrue(settingsSource.contains("Custom Deactivation Delay"))
        XCTAssertFalse(settingsSource.contains("Lightweight"))
        XCTAssertFalse(settingsSource.contains("title: \"Performance\""))

        let suspensionSource = try Self.source(named: "Sumi/Managers/TabSuspensionService.swift")
        XCTAssertTrue(suspensionSource.contains("proactiveTimers"))
        XCTAssertTrue(suspensionSource.contains("armProactiveTimer"))
        XCTAssertTrue(suspensionSource.contains("SumiSuspensionClock"))
        XCTAssertTrue(suspensionSource.contains("revisitCounts"))
        XCTAssertTrue(suspensionSource.contains("defaultMinimumInactiveInterval"))
        XCTAssertFalse(suspensionSource.contains("30 * 60"))
        XCTAssertFalse(suspensionSource.contains("90 * 60"))
        XCTAssertFalse(suspensionSource.contains("launcherRuntimeSuspensionDeferred"))
        XCTAssertFalse(suspensionSource.contains("maximumWarmHiddenWebViewCount"))

        let coordinatorSource = try Self.source(named: "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift")
        XCTAssertTrue(coordinatorSource.contains("hiddenCloneCleanup"))
        XCTAssertFalse(coordinatorSource.contains("suspensionEligibility("))

        let tabScriptSource = try Self.source(named: "Sumi/Models/Tab/Tab+ScriptMessageHandler.swift")
        XCTAssertTrue(tabScriptSource.contains("SumiTabSuspensionUserScript"))
        XCTAssertTrue(tabScriptSource.contains("forMainFrameOnly = true"))
        XCTAssertTrue(tabScriptSource.contains("tabSuspension"))
        XCTAssertTrue(tabScriptSource.contains("canBeSuspended"))
    }

    func testBrowserManagerStartupAndSettingsSurfacesDoNotConstructDisabledRuntimes() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let trackingProbe = TrackingRuntimeProbe()
        let userscriptsProbe = UserscriptsRuntimeProbe()
        let extensionsProbe = ExtensionsRuntimeProbe()
        let trackingModule = makeTrackingModule(
            registry: registry,
            probe: trackingProbe,
            defaults: harness.defaults
        )
        let userscriptsModule = makeUserscriptsModule(
            registry: registry,
            probe: userscriptsProbe
        )
        let extensionsModule = try makeExtensionsModule(
            registry: registry,
            probe: extensionsProbe
        )
        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: trackingModule,
            adBlockingModule: adBlockingModule,
            extensionsModule: extensionsModule,
            userscriptsModule: userscriptsModule
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertEqual(trackingProbe.settingsCount, 0)
        XCTAssertEqual(trackingProbe.dataStoreCount, 0)
        XCTAssertEqual(trackingProbe.serviceCount, 0)
        XCTAssertEqual(userscriptsProbe.managerCount, 0)
        XCTAssertEqual(userscriptsProbe.storeCount, 0)
        XCTAssertEqual(userscriptsProbe.injectorCount, 0)
        XCTAssertEqual(extensionsProbe.managerCount, 0)
        XCTAssertFalse(adBlockingModule.hasLoadedRuntime)
        XCTAssertFalse(userscriptsModule.hasLoadedRuntime)
        XCTAssertFalse(extensionsModule.hasLoadedRuntime)

        let togglesSource = try Self.source(named: "Sumi/Components/Settings/SumiSettingsModuleToggles.swift")
        let privacySource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/SettingsView.swift")

        XCTAssertTrue(togglesSource.contains("SumiSettingsModuleToggleGate"))
        XCTAssertTrue(privacySource.contains("SumiSettingsModuleToggleGate(descriptor: .trackingProtection)"))
        XCTAssertTrue(privacySource.contains("SumiSettingsModuleToggleGate(descriptor: .adBlocking)"))
        XCTAssertTrue(settingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .extensions)"))
        XCTAssertTrue(settingsSource.contains("SumiSettingsModuleToggleGate(descriptor: .userScripts)"))

        assertSourceExcludes(
            togglesSource + privacySource + settingsSource,
            [
                "SumiTrackingProtectionSettings.shared",
                "SumiTrackingProtectionDataStore.shared",
                "SumiContentBlockingService(",
                "SumiAdBlockingModule(",
                "ExtensionManager(",
                "BrowserExtensionSurfaceStore(",
                "NativeMessagingHandler(",
                "SumiScriptsManager(",
                "UserScriptStore(",
                "UserScriptInjector(",
            ],
            context: "Settings surfaces"
        )
    }

    func testDefaultNormalTabAttachesOnlyCoreRuntimeAndNoOptionalModuleAssets() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let trackingProbe = TrackingRuntimeProbe()
        let userscriptsProbe = UserscriptsRuntimeProbe()
        let extensionsProbe = ExtensionsRuntimeProbe()
        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: makeTrackingModule(
                registry: registry,
                probe: trackingProbe,
                defaults: harness.defaults
            ),
            adBlockingModule: adBlockingModule,
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
        let controller = try XCTUnwrap(webView.configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserScriptsProvider)
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiIdentity_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("__sumiTabSuspension"))
        assertNoOptionalModuleScriptsOrHandlers(in: webView.configuration.userContentController)
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertEqual(adBlockingModule.normalTabDecision(for: tab.url).assets, .empty)

        let suspensionScript = try XCTUnwrap(
            tab.normalTabCoreUserScripts().first { $0.source.contains("__sumiTabSuspension") }
        )
        XCTAssertTrue(suspensionScript.forMainFrameOnly)
        XCTAssertEqual(trackingProbe.settingsCount, 0)
        XCTAssertEqual(trackingProbe.dataStoreCount, 0)
        XCTAssertEqual(trackingProbe.serviceCount, 0)
        XCTAssertEqual(userscriptsProbe.managerCount, 0)
        XCTAssertEqual(userscriptsProbe.storeCount, 0)
        XCTAssertEqual(userscriptsProbe.injectorCount, 0)
        XCTAssertEqual(extensionsProbe.managerCount, 0)
    }

    func testEnabledModulesRemainSeparated() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )

        registry.enable(.trackingProtection)
        XCTAssertTrue(registry.isEnabled(.trackingProtection))
        XCTAssertFalse(registry.isEnabled(.adBlocking))

        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)
        adBlockingModule.setEnabled(true)
        XCTAssertTrue(registry.isEnabled(.trackingProtection))
        XCTAssertTrue(registry.isEnabled(.adBlocking))
        XCTAssertEqual(adBlockingModule.status, .enabledButEngineUnavailable)
        XCTAssertEqual(adBlockingModule.assetsIfAvailable(), .empty)
        XCTAssertEqual(
            adBlockingModule.normalTabDecision(for: URL(string: "https://ads.example.com")).assets,
            .empty
        )

        registry.enable(.userScripts)
        XCTAssertTrue(registry.isEnabled(.userScripts))
        XCTAssertFalse(registry.isEnabled(.extensions))

        registry.disable(.userScripts)
        registry.enable(.extensions)
        XCTAssertTrue(registry.isEnabled(.extensions))
        XCTAssertFalse(registry.isEnabled(.userScripts))

        let trackingSettings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        let url = URL(string: "https://www.example.com/path")!
        trackingSettings.setGlobalMode(.enabled)
        trackingSettings.setSiteOverride(.disabled, for: url)
        adBlockingModule.setEnabled(false)

        XCTAssertEqual(trackingSettings.globalMode, .enabled)
        XCTAssertEqual(trackingSettings.override(for: url), .disabled)
        XCTAssertFalse(registry.isEnabled(.adBlocking))
        XCTAssertTrue(registry.isEnabled(.trackingProtection))
    }

    func testAuxiliaryConfigurationsStayLightweight() throws {
        let browserConfiguration = BrowserConfiguration()
        let surfaces = BrowserConfigurationAuxiliarySurface.allCases

        for surface in surfaces {
            let configuration = browserConfiguration.auxiliaryWebViewConfiguration(surface: surface)

            XCTAssertFalse(configuration.userContentController is UserContentController, surface.rawValue)
            XCTAssertFalse(
                configuration.userContentController
                    .sumiUsesNormalTabBrowserServicesKitUserContentController,
                surface.rawValue
            )
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserScriptsProvider, surface.rawValue)
            XCTAssertTrue(configuration.userContentController.userScripts.isEmpty, surface.rawValue)
            XCTAssertNil(configuration.webExtensionController, surface.rawValue)
            assertNoOptionalModuleScriptsOrHandlers(in: configuration.userContentController)
        }

        let faviconConfiguration = browserConfiguration.auxiliaryWebViewConfiguration(surface: .faviconDownload)
        XCTAssertFalse(faviconConfiguration.websiteDataStore.isPersistent)
        XCTAssertFalse(faviconConfiguration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(faviconConfiguration.preferences.javaScriptCanOpenWindowsAutomatically)

        let sourceConfiguration = WKWebViewConfiguration()
        for marker in [
            "__sumiTabSuspension",
            "sumiLinkInteraction_",
            "sumiIdentity_",
            "SUMI_USER_SCRIPT_RUNTIME",
            "sumiGM_",
            "SUMI_EC_PAGE_BRIDGE:",
            "sumiExternallyConnectableRuntime",
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
            XCTAssertFalse(source.contains("SumiContentBlockingService"), relativePath)
            XCTAssertFalse(source.contains("SumiScriptsManager("), relativePath)
            XCTAssertFalse(source.contains("NativeMessagingHandler("), relativePath)
        }
    }

    func testNormalWebViewOwnershipSourceGuards() throws {
        let tabRuntimeSource = try Self.source(named: "Sumi/Models/Tab/Tab+WebViewRuntime.swift")
        let coordinatorSource = try Self.source(named: "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift")
        let browserConfigSource = try Self.source(named: "Sumi/Models/BrowserConfig/BrowserConfig.swift")

        assertSourceExcludes(
            tabRuntimeSource + coordinatorSource + browserConfigSource,
            [
                "createWebViewInternal",
                "createWebViewConfiguration",
                "cacheOptimizedWebViewConfiguration",
                "webViewConfiguration(for:",
            ],
            context: "normal WebView ownership"
        )

        XCTAssertTrue(tabRuntimeSource.contains("func makeNormalTabWebView(reason: String)"))
        XCTAssertTrue(tabRuntimeSource.contains("func ensureWebView()"))
        XCTAssertTrue(tabRuntimeSource.contains("normalTabWebViewConfiguration(reason:"))
        XCTAssertTrue(coordinatorSource.contains("tab.ensureWebView()"))
        XCTAssertTrue(coordinatorSource.contains("tab.makeNormalTabWebView"))
        XCTAssertFalse(coordinatorSource.contains("normalTabWebViewConfiguration"))
        XCTAssertFalse(coordinatorSource.contains("auxiliaryWebViewConfiguration"))
        XCTAssertFalse(coordinatorSource.contains("surface: .glance"))
        XCTAssertFalse(coordinatorSource.contains("FocusableWKWebView(frame: .zero"))
    }

    func testTrackingProtectionManualEnabledOnlySourceGuards() throws {
        for relativePath in [
            "Sumi/Components/Settings/PrivacySettingsView.swift",
            "Sumi/Components/Sidebar/URLBarView.swift",
            "Sumi/Components/Sidebar/URLBarHubPopover.swift",
            "Sumi/Favicons/DDG/SumiDDGFaviconUserContentController.swift",
            "Sumi/Managers/BrowserManager/BrowserManager.swift",
            "Sumi/Models/BrowserConfig/BrowserConfig.swift",
            "Sumi/Models/Tab/Tab+WebViewRuntime.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("SumiContentBlockingService.shared"), relativePath)
        }

        let moduleSource = try Self.source(named: "Sumi/ContentBlocking/SumiTrackingProtectionModule.swift")
        let dataSource = try Self.source(named: "Sumi/ContentBlocking/SumiTrackingProtection.swift")
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        XCTAssertTrue(settingsSource.contains(".accessibilityLabel(\"Update tracker data\")"))
        XCTAssertTrue(settingsSource.contains("await trackingProtectionModule.updateTrackerDataManually()"))
        XCTAssertTrue(settingsSource.contains(".accessibilityLabel(\"Reset to bundled tracker data\")"))
        XCTAssertFalse(settingsSource.contains(".task"))
        XCTAssertFalse(settingsSource.contains(".onAppear"))
        XCTAssertFalse(settingsSource.localizedCaseInsensitiveContains("stale"))
        XCTAssertFalse(settingsSource.localizedCaseInsensitiveContains("automatic update"))
        XCTAssertFalse(settingsSource.localizedCaseInsensitiveContains("browser update"))
        XCTAssertFalse(settingsSource.localizedCaseInsensitiveContains("app update"))

        for source in [moduleSource, dataSource] {
            XCTAssertFalse(source.contains("Timer"))
            XCTAssertFalse(source.contains("scheduledTimer"))
            XCTAssertFalse(source.contains("Task.sleep"))
            XCTAssertFalse(source.localizedCaseInsensitiveContains("stale"))
        }

        let urlHubTests = try Self.source(named: "SumiTests/URLBarTrackingProtectionPresenterTests.swift")
        XCTAssertTrue(urlHubTests.contains("testPresenterForEnabledPolicyUsesFilledShieldToggle"))
        XCTAssertTrue(urlHubTests.contains("testToggleOverrideSemanticsUseCurrentEffectivePolicyOnly"))
    }

    func testUserscriptsEnabledOnlySourceGuards() throws {
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

        let browserManagerSource = try Self.source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")
        let userscriptsModuleSource = try Self.source(named: "Sumi/Managers/SumiScripts/SumiUserscriptsModule.swift")
        let userscriptsManagerSource = try Self.source(named: "Sumi/Managers/SumiScripts/SumiScriptsManager.swift")
        let tabRuntimeSource = try Self.source(named: "Sumi/Models/Tab/Tab+WebViewRuntime.swift")

        XCTAssertFalse(userscriptsManagerSource.contains("SumiScripts.enabled"))
        XCTAssertTrue(browserManagerSource.contains("let userscriptsModule: SumiUserscriptsModule"))
        XCTAssertFalse(browserManagerSource.contains("let sumiScriptsManager"))
        XCTAssertFalse(browserManagerSource.contains("self.sumiScriptsManager"))
        XCTAssertFalse(browserManagerSource.contains("SumiScriptsManager("))
        XCTAssertTrue(tabRuntimeSource.contains("var scripts = normalTabCoreUserScripts()"))
        XCTAssertTrue(tabRuntimeSource.contains("userscriptsModule.normalTabUserScripts"))

        assertSourceExcludes(
            tabRuntimeSource + userscriptsModuleSource,
            [
                "SUMI_USER_SCRIPT_RUNTIME",
                "sumiGM_",
                "UserScriptGMBridge",
            ],
            context: "disabled userscripts boundary"
        )

        let installedAdapterSource = try Self.source(
            named: "Sumi/Managers/SumiScripts/SumiInstalledUserScriptAdapters.swift"
        )
        XCTAssertTrue(installedAdapterSource.contains("sumiGM_"))
        XCTAssertTrue(installedAdapterSource.contains("UserScriptGMBridge"))
    }

    func testExtensionsNativeMessagingEnabledOnlyAsyncSourceGuards() throws {
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

        let browserManagerSource = try Self.source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")
        XCTAssertTrue(browserManagerSource.contains("let extensionsModule: SumiExtensionsModule"))
        XCTAssertFalse(browserManagerSource.contains("let extensionManager"))
        XCTAssertFalse(browserManagerSource.contains("self.extensionManager"))
        XCTAssertFalse(browserManagerSource.contains("ExtensionManager("))

        for relativePath in [
            "Sumi/Managers/BrowserManager/BrowserManager.swift",
            "Sumi/Managers/BrowserManager/BrowserManager+DialogsUtilities.swift",
            "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift",
            "Sumi/Components/Settings/SettingsView.swift",
            "Sumi/Components/Settings/SumiSettingsModuleToggles.swift",
            "Sumi/Components/Extensions/ExtensionActionView.swift",
            "Navigation/Sidebar/SidebarHeader.swift",
            "Sumi/Models/BrowserConfig/BrowserConfig.swift",
            "Sumi/Models/Tab/Tab+WebViewRuntime.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("NativeMessagingHandler("), relativePath)
            XCTAssertFalse(source.contains("NativeMessagingProcessSession"), relativePath)
        }

        let delegateSource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
        )
        let nativeMessagingSource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/NativeMessagingHandler.swift"
        )
        XCTAssertTrue(delegateSource.contains("NativeMessagingHandler("))
        XCTAssertTrue(nativeMessagingSource.contains("DispatchSource.makeReadSource"))
        XCTAssertTrue(nativeMessagingSource.contains("DispatchSource.makeWriteSource"))
        assertSourceExcludes(
            nativeMessagingSource,
            [
                "readDataToEndOfFile",
                "readData(ofLength",
                "availableData",
                "waitUntilExit",
                "DispatchSemaphore",
                "DispatchGroup",
                "group.wait",
                ".write(contentsOf",
            ],
            context: "NativeMessagingHandler"
        )
    }

    func testAdBlockingSkeletonStaysInert() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let module = SumiAdBlockingModule(moduleRegistry: registry)

        XCTAssertFalse(module.isEnabled)
        XCTAssertEqual(module.status, .disabled)
        XCTAssertEqual(module.assetsIfAvailable(), .empty)
        XCTAssertEqual(module.normalTabDecision(for: nil).status, .disabled)
        XCTAssertEqual(module.normalTabDecision(for: nil).assets, .empty)
        XCTAssertFalse(module.hasLoadedRuntime)

        module.setEnabled(true)

        XCTAssertTrue(module.isEnabled)
        XCTAssertEqual(module.status, .enabledButEngineUnavailable)
        XCTAssertEqual(module.assetsIfAvailable(), .empty)
        XCTAssertEqual(module.normalTabDecision(for: nil).status, .enabledButEngineUnavailable)
        XCTAssertEqual(module.normalTabDecision(for: nil).assets, .empty)
        XCTAssertFalse(module.hasLoadedRuntime)

        let adBlockingSource = try Self.source(named: "Sumi/ContentBlocking/SumiAdBlockingModule.swift")
        assertSourceExcludes(
            adBlockingSource,
            [
                "adblock_rust",
                "adblock-rust",
                "EasyList",
                "EasyPrivacy",
                "SumiContentBlockingService",
                "SumiTrackingProtectionModule",
                "SumiTrackingRuleListProvider",
                "SumiTrackingRuleListPipeline",
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
                "filterList",
                "filter list",
            ],
            context: "SumiAdBlockingModule"
        )
        XCTAssertFalse(adBlockingSource.localizedCaseInsensitiveContains("cosmetic"))
        XCTAssertFalse(adBlockingSource.localizedCaseInsensitiveContains("scriptlet"))

        for relativePath in [
            "Sumi.xcodeproj/project.pbxproj",
            "Vendor/DDG/BrowserServicesKit/Package.swift",
            "Vendor/DDG/URLPredictor/Package.swift",
        ] {
            let source = try Self.source(named: relativePath)
            assertSourceExcludes(
                source,
                [
                    "Cargo.toml",
                    "cargo",
                    "adblock_rust",
                    "adblock-rust",
                    "EasyList",
                    "EasyPrivacy",
                ],
                context: relativePath
            )
        }
    }

    func testHistoryQueriesStayBounded() throws {
        let searchSource = try Self.source(named: "Sumi/Managers/SearchManager/SearchManager.swift")
        let pageViewModelSource = try Self.source(named: "Sumi/History/HistoryPageViewModel.swift")
        let historyManagerSource = try Self.source(named: "Sumi/Managers/History/HistoryManager.swift")
        let providerSource = try Self.source(named: "Sumi/Managers/History/HistoryViewDataProvider.swift")
        let storeSource = try Self.source(named: "Sumi/Managers/History/HistoryStore.swift")
        let uiStartupSource = [
            searchSource,
            pageViewModelSource,
            historyManagerSource,
            providerSource,
            try Self.source(named: "Sumi/History/SumiHistoryMenu.swift"),
            try Self.source(named: "Sumi/Services/SumiBrowsingDataCleanupService.swift"),
        ].joined(separator: "\n")

        assertSourceExcludes(
            uiStartupSource,
            [
                "store.visits(",
                "dataProvider.items(for:",
                "visitRecords(matching:",
                "rawVisits",
                "allItems",
                "allHistory",
                "allVisits",
                "loadAll",
                "fetchAll",
                "DispatchSemaphore",
                "DispatchGroup",
                "group.wait",
            ],
            context: "history UI/startup paths"
        )

        XCTAssertTrue(pageViewModelSource.contains("historyManager.historyPage"))
        XCTAssertTrue(pageViewModelSource.contains("pageSize = HistoryStore.defaultHistoryPageLimit"))
        XCTAssertTrue(providerSource.contains("store.fetchHistoryPage"))
        XCTAssertTrue(providerSource.contains("store.fetchSitePage"))
        XCTAssertTrue(storeSource.contains("descriptor.fetchLimit = limit"))
        XCTAssertTrue(storeSource.contains("descriptor.fetchOffset = offset"))
        XCTAssertTrue(storeSource.contains("clearAllExplicit"))
        XCTAssertTrue(storeSource.contains("deleteVisits("))
        XCTAssertTrue(searchSource.contains("historySuggestionTask"))
        XCTAssertTrue(searchSource.contains("historySuggestionTask?.cancel()"))
        XCTAssertTrue(searchSource.contains("Task.isCancelled"))
        XCTAssertTrue(searchSource.contains("activeWebSuggestionGeneration"))
        XCTAssertTrue(searchSource.contains("historyManager.searchSuggestions(matching: query, limit: 20)"))
    }

    func testNoAutomaticUpdatesOnboardingTelemetryOrDiagnostics() throws {
        let settingsSource = try Self.combinedSwiftSource(in: "Sumi/Components/Settings")
        assertSourceExcludes(
            settingsSource,
            [
                "first-run",
                "first run",
                "module diagnostics",
                "unified site settings",
                "stale tracker",
                "stale ad",
                "automatic tracker",
                "automatic ad",
                "browser update",
                "app update",
            ],
            context: "Settings sources"
        )

        let productionSources = try [
            Self.combinedSwiftSource(in: "App"),
            Self.combinedSwiftSource(in: "Sumi"),
            Self.combinedSwiftSource(in: "Settings"),
            Self.combinedSwiftSource(in: "Navigation"),
            Self.combinedSwiftSource(in: "UI"),
            Self.combinedSwiftSource(in: "CommandPalette"),
        ].joined(separator: "\n")
        assertSourceExcludes(
            productionSources,
            [
                "PixelKit",
                "ProductAnalytics",
                "DDGPixel",
                "module diagnostics",
                "unified site settings",
                "automaticTracker",
                "automaticAd",
                "autoTracker",
                "autoAdList",
            ],
            context: "production Swift sources"
        )

        let onboardingSwiftFiles = try Self.relativeFiles(in: "Onboarding")
            .filter { $0.hasSuffix(".swift") }
        XCTAssertTrue(onboardingSwiftFiles.isEmpty)
        XCTAssertFalse(productionSources.contains("OnboardingView"))
        XCTAssertFalse(productionSources.contains("FirstRun"))
        XCTAssertTrue(productionSources.contains("didFinishOnboardingKey"))
        XCTAssertTrue(productionSources.contains("didFinishOnboardingKey: true"))
    }

    private func makeTrackingModule(
        registry: SumiModuleRegistry,
        probe: TrackingRuntimeProbe,
        defaults: UserDefaults
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
                        .appendingPathComponent(
                            "SumiPrompt20Tracking-\(UUID().uuidString)",
                            isDirectory: true
                        )
                )
            },
            contentBlockingServiceFactory: { _, _ in
                probe.serviceCount += 1
                return SumiContentBlockingService(policy: .disabled)
            }
        )
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
            "SUMI_EC_PAGE_BRIDGE:",
            "sumiExternallyConnectableRuntime",
            "SumiAdBlocking",
            "sumiAdBlocking",
            "adBlocking",
            "ad-block",
            "adblock",
        ] {
            XCTAssertFalse(combined.contains(marker), marker, file: file, line: line)
        }
    }

    private func assertSourceExcludes(
        _ source: String,
        _ patterns: [String],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for pattern in patterns {
            XCTAssertFalse(
                source.contains(pattern),
                "\(pattern) should not appear in \(context)",
                file: file,
                line: line
            )
        }
    }

    private static func source(named relativePath: String) throws -> String {
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func combinedSwiftSource(in relativeDirectory: String) throws -> String {
        let fileURLs = try relativeFiles(in: relativeDirectory)
            .filter { $0.hasSuffix(".swift") }
            .map { repoRoot.appendingPathComponent($0) }

        return try fileURLs
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private static func relativeFiles(in relativeDirectory: String) throws -> [String] {
        let directoryURL = repoRoot.appendingPathComponent(relativeDirectory)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }
        let fileURLs = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL } ?? []

        return fileURLs
            .filter { $0.hasDirectoryPath == false }
            .map { url in
                String(url.path.dropFirst(repoRoot.path.count + 1))
            }
            .sorted()
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class TrackingRuntimeProbe {
    var settingsCount = 0
    var dataStoreCount = 0
    var serviceCount = 0
}

private final class UserscriptsRuntimeProbe {
    var managerCount = 0
    var storeCount = 0
    var injectorCount = 0
}

private final class ExtensionsRuntimeProbe {
    var managerCount = 0
}
