import AppKit
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
        XCTAssertEqual(SumiMemorySaverCustomDelay.clamped(30), 60)
        XCTAssertEqual(SumiMemorySaverCustomDelay.clamped(5 * 60), 5 * 60)
        XCTAssertEqual(SumiMemorySaverCustomDelay.clamped(48 * 60 * 60), 2 * 60 * 60)

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
        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: adBlockingModule,
            extensionsModule: extensionsModule,
            userscriptsModule: userscriptsModule
        )

        XCTAssertNotNil(browserManager.currentProfile)
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
        XCTAssertFalse(privacySource.contains("SumiSettingsModuleToggleGate(descriptor: .trackingProtection)"))
        XCTAssertFalse(privacySource.contains("SumiSettingsModuleToggleGate(descriptor: .adBlocking)"))
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

    func testStartupRestoreDoesNotBlockOnFaviconCacheLoad() throws {
        let persistenceSource = try Self.source(named: "Sumi/Managers/TabManager/TabManager+Persistence.swift")
        XCTAssertFalse(persistenceSource.contains("waitUntilSharedFaviconManagerLoaded"))
        XCTAssertFalse(persistenceSource.contains("async let faviconLoadTask"))
        XCTAssertFalse(persistenceSource.contains("await faviconLoadTask"))
        XCTAssertTrue(persistenceSource.contains("loadsCachedFaviconOnInit: false"))

        let startupRestoreSource = try Self.source(named: "Sumi/Managers/TabManager/TabManager+StartupRestore.swift")
        XCTAssertTrue(startupRestoreSource.contains("loadsCachedFaviconOnInit: false"))
    }

    func testFaviconV2StartupDoesNotRestoreOldImageCacheOrManager() throws {
        let systemSource = try Self.source(named: "Sumi/Favicons/SumiFaviconSystem.swift")
        let tabFaviconStoreSource = try Self.source(named: "Sumi/Models/Tab/TabFaviconStore.swift")

        XCTAssertTrue(systemSource.contains("let service: SumiFaviconService"))
        XCTAssertFalse(systemSource.contains("FaviconManager"))
        XCTAssertFalse(systemSource.contains("SumiBookmarkMirrorManager"))
        XCTAssertFalse(systemSource.contains("SumiDDGBookmarkFavicon"))
        XCTAssertTrue(tabFaviconStoreSource.contains("service.cachedPreparedImage"))
        XCTAssertTrue(tabFaviconStoreSource.contains("service.preparedImage"))
        XCTAssertFalse(tabFaviconStoreSource.contains("FaviconImageCache"))
    }

    func testStoredLaunchersLazyLoadVisibleFaviconsOnly() throws {
        let tabFaviconStoreSource = try Self.source(named: "Sumi/Models/Tab/TabFaviconStore.swift")
        XCTAssertTrue(tabFaviconStoreSource.contains("loadCachedLauncherImage("))
        XCTAssertTrue(tabFaviconStoreSource.contains("loadCachedDisplayImage("))
        XCTAssertTrue(tabFaviconStoreSource.contains("context: .pinnedLauncher"))
        XCTAssertTrue(tabFaviconStoreSource.contains("priority: .pinnedLauncher"))
        XCTAssertTrue(tabFaviconStoreSource.contains("SumiFaviconSystem.shared.service.preparedImage"))
        XCTAssertFalse(tabFaviconStoreSource.contains("loadFavicons() async"))

        let pinnedGridSource = try Self.source(named: "Sumi/Components/Sidebar/PinnedButtons/PinnedGrid.swift")
        XCTAssertTrue(pinnedGridSource.contains(".task(id: storedFaviconLoadKey)"))
        XCTAssertTrue(pinnedGridSource.contains("TabFaviconStore.loadCachedLauncherImage("))
        XCTAssertTrue(pinnedGridSource.contains("faviconPartition: browserManager.tabManager.resolvedFaviconPartition"))
        XCTAssertTrue(pinnedGridSource.contains("partition: faviconPartition"))

        let shortcutRowSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/ShortcutSidebarRow.swift")
        XCTAssertTrue(shortcutRowSource.contains(".task(id: storedFaviconLoadKey)"))
        XCTAssertTrue(shortcutRowSource.contains("currentLoadedStoredFavicon ?? ShortcutPin.cachedLaunchFavicon("))
        XCTAssertFalse(shortcutRowSource.contains("guard liveTab == nil, pin.iconAsset == nil else { return }"))
        XCTAssertTrue(shortcutRowSource.contains("TabFaviconStore.loadCachedLauncherImage("))
        XCTAssertTrue(shortcutRowSource.contains("browserManager.tabManager.resolvedFaviconPartition"))
        XCTAssertTrue(shortcutRowSource.contains("partition: faviconPartition"))
        XCTAssertTrue(shortcutRowSource.contains("if let liveTab, !liveTab.faviconIsTemplateGlobePlaceholder"))

        let tabExtensionSource = try Self.source(named: "Sumi/Tab/DDGExtensions/FaviconsTabExtension.swift")
        XCTAssertFalse(tabExtensionSource.contains("guard faviconManagement.isCacheLoaded else { return }"))
        XCTAssertFalse(tabExtensionSource.contains("guard tab.requiresPrimaryWebView else"))
        XCTAssertTrue(tabExtensionSource.contains("cachedFaviconLoadingTask = Task"))

        let shortcutPinSource = try Self.source(named: "Sumi/Models/Tab/ShortcutPin.swift")
        XCTAssertTrue(shortcutPinSource.contains("storedFaviconImage(partition: .regular(executionProfileId ?? profileId))"))
        XCTAssertTrue(shortcutPinSource.contains("context: .pinnedLauncher"))

        XCTAssertTrue(pinnedGridSource.contains("LivePinnedTileContent("))
        XCTAssertTrue(pinnedGridSource.contains("let launcherFavicon = currentCachedStoredFavicon"))
        XCTAssertTrue(pinnedGridSource.contains("hasLauncherFavicon: launcherFavicon != nil"))
    }

    func testHistoryAndBookmarksLazyLoadPersistedFavicons() throws {
        let bookmarksSource = try Self.source(named: "Sumi/Bookmarks/SumiBookmarksTabRootView.swift")
        XCTAssertTrue(bookmarksSource.contains(".task(id: faviconLoadID)"))
        XCTAssertTrue(bookmarksSource.contains("TabFaviconStore.loadCachedDisplayImage("))
        XCTAssertTrue(bookmarksSource.contains("partition: faviconPartition"))
        XCTAssertTrue(bookmarksSource.contains("context: .historyBookmarkRow"))
        XCTAssertTrue(bookmarksSource.contains("priority: .historyBookmarkVisibleRow"))
        XCTAssertTrue(bookmarksSource.contains("faviconImage = loadedImage ?? cachedFaviconImage"))
        XCTAssertFalse(bookmarksSource.contains("Tab.getCachedFavicon(for: cacheKey)"))

        let historySource = try Self.source(named: "Sumi/History/SumiHistoryTabRootView.swift")
        XCTAssertTrue(historySource.contains("TabFaviconStore.getCachedImage("))
        XCTAssertTrue(historySource.contains("TabFaviconStore.loadCachedDisplayImage("))
        XCTAssertTrue(historySource.contains("partition: partition"))
        XCTAssertTrue(historySource.contains("context: .historyBookmarkRow"))
        XCTAssertTrue(historySource.contains("priority: .historyBookmarkVisibleRow"))
        XCTAssertTrue(historySource.contains("image = loadedImage ?? cachedImage"))
        XCTAssertFalse(historySource.contains("TabFaviconStore.getCachedImage(for: cacheKey)"))
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

    func testFaviconPipelineUsesV2BlobStoreDecodePipelineAndPreparedCacheOnly() throws {
        let blobStoreSource = try Self.source(named: "Sumi/Favicons/V2/SumiFaviconBlobStore.swift")
        XCTAssertTrue(blobStoreSource.contains("sha256Hex"))
        XCTAssertTrue(blobStoreSource.contains("pageMappings"))
        XCTAssertTrue(blobStoreSource.contains("candidateMappings"))
        XCTAssertTrue(blobStoreSource.contains("diskBudgetBytes"))

        let preparedPipelineSource = try Self.source(named: "Sumi/Favicons/V2/SumiPreparedFaviconPipeline.swift")
        XCTAssertTrue(preparedPipelineSource.contains("CGImageSourceCreateThumbnailAtIndex"))
        XCTAssertTrue(preparedPipelineSource.contains("kCGImageSourceThumbnailMaxPixelSize"))
        XCTAssertTrue(preparedPipelineSource.contains("bestImageIndex"))
        XCTAssertTrue(preparedPipelineSource.contains("CGContext("))
        XCTAssertFalse(preparedPipelineSource.contains("lockFocus"))

        let preparedCacheSource = try Self.source(named: "Sumi/Favicons/V2/SumiPreparedFaviconCache.swift")
        XCTAssertTrue(preparedCacheSource.contains("preparedMemoryBudgetBytes"))
        XCTAssertTrue(preparedCacheSource.contains("totalCostLimit"))

        let systemSource = try Self.source(named: "Sumi/Favicons/SumiFaviconSystem.swift")
        XCTAssertFalse(systemSource.contains("\"favicons.sqlite\""))
        XCTAssertFalse(systemSource.contains("FaviconManager"))
    }

    func testCachedProtectionAttachmentPlanDropsEncodedRuleListsAfterPreparation() throws {
        let source = try Self.source(named: "Sumi/ContentBlocking/SumiProtectionCoordinator.swift")

        XCTAssertTrue(source.contains("retainEncodedRuleListsInPreparedPolicy: false"))
        XCTAssertFalse(source.contains("cachedAttachmentPlan = plan"))
        XCTAssertEqual(
            source.components(separatedBy: "cachedAttachmentPlan = metadataOnlyGlobalAttachmentPlan(plan)").count - 1,
            2
        )
    }

    func testOffProtectionDecisionDoesNotInitializeSiteOverrideStore() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let settings = SumiProtectionSettings(userDefaults: harness.defaults)
        settings.setAppliedLevel(.off)
        var sitePolicyFactoryCalls = 0
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: {
                sitePolicyFactoryCalls += 1
                return AdblockSitePolicyStore(userDefaults: harness.defaults)
            }
        )
        let coordinator = SumiProtectionCoordinator(
            settings: settings,
            adBlockingModule: adBlockingModule,
            moduleRegistry: registry
        )

        _ = coordinator.normalTabDecision(
            for: URL(string: "https://example.com/path"),
            profileId: nil
        )

        XCTAssertEqual(sitePolicyFactoryCalls, 0)
    }

    func testDefaultNormalTabAttachesOnlyCoreRuntimeAndNoOptionalModuleAssets() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let userscriptsProbe = UserscriptsRuntimeProbe()
        let extensionsProbe = ExtensionsRuntimeProbe()
        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
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
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserScriptsProvider)
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("__sumiTabSuspension"))
        assertNoOptionalModuleScriptsOrHandlers(in: webView.configuration.userContentController)
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertFalse(adBlockingModule.hasLoadedRuntime)

        let suspensionScript = try XCTUnwrap(
            tab.normalTabCoreUserScripts().first { $0.source.contains("__sumiTabSuspension") }
        )
        XCTAssertTrue(suspensionScript.forMainFrameOnly)
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
        XCTAssertFalse(adBlockingModule.hasLoadedRuntime)

        registry.enable(.userScripts)
        XCTAssertTrue(registry.isEnabled(.userScripts))
        XCTAssertFalse(registry.isEnabled(.extensions))

        registry.disable(.userScripts)
        registry.enable(.extensions)
        XCTAssertTrue(registry.isEnabled(.extensions))
        XCTAssertFalse(registry.isEnabled(.userScripts))

        let protectionSettings = SumiProtectionSettings(userDefaults: harness.defaults)
        let url = URL(string: "https://www.example.com/path")!
        protectionSettings.setLevel(.protection)
        protectionSettings.setAppliedLevel(.protection)
        adBlockingModule.setSiteOverride(.disabled, for: url)
        adBlockingModule.setEnabled(false)

        XCTAssertEqual(protectionSettings.level, .protection)
        XCTAssertEqual(protectionSettings.appliedLevel, .protection)
        XCTAssertEqual(adBlockingModule.siteOverride(for: url), .disabled)
        XCTAssertFalse(registry.isEnabled(.adBlocking))
        XCTAssertTrue(registry.isEnabled(.trackingProtection))
    }

    func testAuxiliaryConfigurationsStayLightweight() throws {
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

        let faviconSource = try Self.source(named: "Sumi/Favicons/V2/SumiFaviconFetchScheduler.swift")
        XCTAssertFalse(Self.fileExists("Sumi/Favicons/DDG/Model/FaviconDownloader.swift"))
        XCTAssertFalse(faviconSource.contains("WKWebViewConfiguration()"))
        XCTAssertFalse(faviconSource.contains("normalTabWebViewConfiguration("))

        for relativePath in [
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
            "Sumi/UserScripts/SumiNormalTabBrowserServicesKitUserContentControllerAdapter.swift",
            "Sumi/UserScripts/SumiNormalTabUserScripts.swift",
            "Sumi/Managers/BrowserManager/BrowserManager.swift",
            "Sumi/Models/BrowserConfig/BrowserConfig.swift",
            "Sumi/Models/Tab/Tab+WebViewRuntime.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("SumiContentBlockingService.shared"), relativePath)
        }

        let settingsSource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")
        let trackingSettingsSource = settingsSource

        XCTAssertFalse(settingsSource.contains("LegacyTrackingProtectionRuntimeSettingsView"))
        XCTAssertFalse(settingsSource.contains(".accessibilityLabel(\"Update tracker data\")"))
        XCTAssertFalse(settingsSource.contains("await trackingProtectionModule.updateTrackerDataManually()"))
        XCTAssertFalse(settingsSource.contains(".accessibilityLabel(\"Reset to bundled tracker data\")"))
        XCTAssertFalse(trackingSettingsSource.contains(".task"))
        XCTAssertFalse(trackingSettingsSource.contains(".onAppear"))
        XCTAssertFalse(trackingSettingsSource.localizedCaseInsensitiveContains("stale"))
        XCTAssertFalse(trackingSettingsSource.localizedCaseInsensitiveContains("automatic update"))
        XCTAssertFalse(trackingSettingsSource.localizedCaseInsensitiveContains("browser update"))
        XCTAssertFalse(trackingSettingsSource.localizedCaseInsensitiveContains("app update"))

        for source in [
            try Self.source(named: "Sumi/ContentBlocking/SumiProtectionCoordinator.swift"),
            try Self.source(named: "Sumi/ContentBlocking/SumiContentBlockingService.swift"),
        ] {
            XCTAssertFalse(source.contains("Timer"))
            XCTAssertFalse(source.contains("scheduledTimer"))
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
        let portSessionSource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingPortSession.swift"
        )
        let relaySource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift"
        )
        XCTAssertTrue(delegateSource.contains("safariNativeMessagingHost.handleSendMessage"))
        XCTAssertTrue(delegateSource.contains("safariNativeMessagingHost.handleConnect"))
        XCTAssertTrue(portSessionSource.contains("WKWebExtension.MessagePort"))
        XCTAssertTrue(relaySource.contains("SumiNativeMessagingRelay"))
        XCTAssertFalse(
            relaySource.contains(
                "ChromeMV3NativeMessagingInternalRuntime"
            )
        )
        let processCallToken = "Process" + "("
        assertSourceExcludes(
            portSessionSource + relaySource,
            [
                processCallToken,
                "NativeMessagingProcessSession",
                "DispatchSource",
                "readDataToEndOfFile",
                "readData(ofLength",
                "availableData",
                "waitUntilExit",
                "DispatchSemaphore",
                "DispatchGroup",
                "group.wait",
                ".write(contentsOf",
            ],
            context: "Safari native messaging foundation"
        )
    }

    func testAdBlockingPreparedBundleBoundaryStaysInertUntilNeeded() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let module = SumiAdBlockingModule(moduleRegistry: registry)

        XCTAssertFalse(module.isEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)

        module.setEnabled(true)

        XCTAssertTrue(module.isEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)

        let adBlockingSource = try Self.source(named: "Sumi/ContentBlocking/SumiAdBlockingModule.swift")
        assertSourceExcludes(
            adBlockingSource,
            [
                "adblock_rust",
                "adblock-rust",
                "EasyList",
                "EasyPrivacy",
                "SumiTrackingProtectionModule",
                "SumiTrackingRuleListProvider",
                "SumiTrackingRuleListPipeline",
                "SumiAdBlockingModuleStatus",
                "SumiAdblockCurrentTabDiagnostics",
                "SumiAdblockAttachmentDiagnostics",
                "embeddedAdblockBundleSnapshot",
                "installEmbeddedAdblockBundle",
                "SumiEmbeddedAdblockBundleCatalog",
                "requestEmbeddedBundleInstall",
                "contentRuleListDefinitions(for allowedKinds",
                "runtimeGenerated",
                "ContentBlockerRulesBuilder",
                "TrackerRadarKit",
                "WKUserScript",
                "addUserScript",
                "addScriptMessageHandler",
                "URLSession",
                "Timer",
                "scheduledTimer",
                "download",
                "filterList",
                "filter list",
            ],
            context: "SumiAdBlockingModule"
        )

        for relativePath in [
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
            try Self.source(named: "App/SumiCommands.swift"),
            try Self.source(named: "App/SumiHistoryCommands.swift"),
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
            Self.combinedSwiftSource(in: "FloatingBar"),
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

    private static func testFaviconImage(side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
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

    private static func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(relativePath).path)
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
