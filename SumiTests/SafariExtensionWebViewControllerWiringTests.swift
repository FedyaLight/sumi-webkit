import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionWebViewControllerWiringTests: SafariExtensionWebViewControllerWiringTestCase {
    func testAttachExtensionControllerIfNeededAssignsProfileController() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        let expectedController = manager.ensureExtensionController(for: profile.id)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        XCTAssertTrue(manager.attachExtensionControllerIfNeeded(to: webView, for: tab))
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
    }

    func testExtensionRuntimeLiveLookupPrefersWindowOwnedTrackedWebView() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        let browserManager = makeBrowserManager(profile: profile)
        let windowRegistry = WindowRegistry()
        let coordinator = WebViewCoordinator()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = coordinator
        browserManager.tabManager = TabManager(
            runtimePorts: BrowserTabManagerRuntimePortsFactory.registry(for: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Work",
            profileId: profile.id
        )
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        manager.attach(browserManager: browserManager)

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://example.com")!
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        windowState.currentTabId = tab.id
        let staleWebView = WKWebView()
        let trackedWebView = WKWebView()
        tab.assignWebViewToWindow(staleWebView, windowId: windowState.id)
        coordinator.setWebView(trackedWebView, for: tab.id, in: windowState.id)

        XCTAssertIdentical(manager.resolvedLiveWebView(for: tab), trackedWebView)
        let liveWebViews = manager.liveWebViews(for: tab)
        XCTAssertEqual(liveWebViews.count, 1)
        XCTAssertIdentical(liveWebViews.first, trackedWebView)
    }

    func testProfileExtensionControllerUsesSumiNativeMessagingDelegate() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let controller = manager.ensureExtensionController(for: profile.id)
        let delegateObject = try XCTUnwrap(controller.delegate.map { $0 as AnyObject })
        let delegate = try XCTUnwrap(controller.delegate as NSObjectProtocol?)
        let sendSelector = #selector(
            WKWebExtensionControllerDelegate.webExtensionController(
                _:sendMessage:toApplicationWithIdentifier:for:replyHandler:
            )
        )
        let connectSelector = #selector(
            WKWebExtensionControllerDelegate.webExtensionController(
                _:connectUsing:for:completionHandler:
            )
        )

        XCTAssertTrue(delegateObject === manager.controllerDelegateBridge)
        XCTAssertTrue(delegate.responds(to: sendSelector))
        XCTAssertTrue(delegate.responds(to: connectSelector))
        XCTAssertIdentical(
            browserConfiguration.webViewConfiguration.webExtensionController,
            controller
        )
    }

    func testExtensionWebViewReturnsNilWithoutControllerOnLoadedPage() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        let tab = makeTab(profileId: profile.id, url: URL(string: "https://example.com")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)
        webView.load(URLRequest(url: URL(string: "https://example.com")!))

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        XCTAssertNil(manager.extensionWebView(for: tab, extensionContext: extensionContext))
    }

    func testWebViewBindingPolicyOnlyLateBindsBlankTargets() {
        XCTAssertTrue(
            ExtensionRuntimeWebViewBindingPolicy.canLateBindController(currentURL: nil)
        )
        XCTAssertTrue(
            ExtensionRuntimeWebViewBindingPolicy.canLateBindController(
                currentURL: URL(string: "about:blank")
            )
        )
        XCTAssertFalse(
            ExtensionRuntimeWebViewBindingPolicy.canLateBindController(
                currentURL: URL(string: "https://example.com")
            )
        )
    }

    func testExtensionWebViewReturnsProfileMatchedController() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        let expectedController = manager.ensureExtensionController(for: profile.id)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        let resolvedWebView = try XCTUnwrap(
            manager.extensionWebView(for: tab, extensionContext: extensionContext)
        )
        XCTAssertIdentical(
            resolvedWebView.configuration.webExtensionController,
            expectedController
        )
    }

    func testExtensionWebViewRejectsCrossProfileContext() async throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profileA,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profileB.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(profileId: profileB.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profileA
        )
        XCTAssertNil(manager.extensionWebView(for: tab, extensionContext: extensionContext))
    }

    func testIsTabEligibleForCurrentExtensionRuntimeBlocksEphemeralTabs() throws {
        let container = try makeTestContainer()
        let ephemeralProfile = Profile.createEphemeral()
        let manager = makeManager(
            context: container.mainContext,
            profile: ephemeralProfile
        ).manager
        manager.tabOpenNotificationGeneration = 7

        let browserManager = makeBrowserManager(profile: ephemeralProfile)

        let tab = makeTab(
            profileId: ephemeralProfile.id,
            url: URL(string: "https://example.com")!
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.tabOpenNotificationGeneration

        XCTAssertTrue(ephemeralProfile.isEphemeral)
        XCTAssertTrue(tab.isEphemeral)
        XCTAssertFalse(manager.isTabEligibleForCurrentExtensionRuntime(tab))
    }

    func testNotifyTabActivatedSkipsGenerationEligibleEphemeralTabs() throws {
        let container = try makeTestContainer()
        let ephemeralProfile = Profile.createEphemeral()
        let manager = makeManager(
            context: container.mainContext,
            profile: ephemeralProfile
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: ephemeralProfile.id)
        manager.extensionsLoaded = true
        manager.tabOpenNotificationGeneration = 9

        let browserManager = makeBrowserManager(profile: ephemeralProfile)
        manager.attach(browserManager: browserManager)

        let tab = makeTab(
            profileId: ephemeralProfile.id,
            url: URL(string: "https://example.com")!
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.tabOpenNotificationGeneration

        var activatedTabIDs: [UUID] = []
        manager.testHooks.didActivateTab = { activatedTabIDs.append($0) }

        XCTAssertTrue(tab.isEphemeral)
        manager.notifyTabActivated(newTab: tab, previous: nil)

        XCTAssertTrue(activatedTabIDs.isEmpty)
    }

    func testExtensionTabAdapterDoesNotReturnWebViewWithoutController() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true
        manager.tabOpenNotificationGeneration = 3

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com",
            in: browserManager.tabManager.spaceStateOwner.currentSpace,
            activate: false
        )
        tab.profileId = profile.id
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.tabOpenNotificationGeneration

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        let adapter = try XCTUnwrap(manager.adapterResolutionOwner.stableAdapter(for: tab))
        XCTAssertNil(adapter.webView(for: extensionContext))
    }

    func testNormalTabWebViewIncludesProfileExtensionController() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            initialProfileProvider: { profile }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        extensionsModule.attach(runtime: BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager))

        let scratchDirectory = try makeScratchDirectory()
        let manager = try XCTUnwrap(extensionsModule.managerIfEnabled())
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "WebViewWiringExtension"
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)
        manager.extensionsLoaded = true

        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "about:blank",
            in: browserManager.tabManager.spaceStateOwner.currentSpace,
            activate: false
        )
        tab.profileId = profile.id

        let webView = try XCTUnwrap(tab.makeNormalTabWebView(reason: "SafariExtensionWebViewControllerWiringTests"))
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            manager.ensureExtensionController(for: profile.id)
        )
    }

    func testNormalTabSetupDelaysOpenNotificationUntilInitialDocumentWarmup() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            initialProfileProvider: { profile }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        extensionsModule.attach(runtime: BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager))
        browserManager.tabManager = TabManager(
            runtimePorts: BrowserTabManagerRuntimePortsFactory.registry(for: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Work",
            profileId: profile.id
        )

        let scratchDirectory = try makeScratchDirectory()
        let manager = try XCTUnwrap(extensionsModule.managerIfEnabled())
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)
        manager.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        manager.extensionsLoaded = true

        XCTAssertFalse(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))

        let pageURL = URL(string: "https://example.com/login")!
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: pageURL.absoluteString,
            in: space,
            activate: false
        )
        tab.profileId = profile.id

        var didOpenCount = 0
        let didOpenExpectation = expectation(description: "didOpenTab after warmup")
        manager.testHooks.didOpenTab = { tabID in
            guard tabID == tab.id else { return }
            didOpenCount += 1
            if didOpenCount == 1 {
                didOpenExpectation.fulfill()
            }
        }
        defer {
            manager.testHooks.didOpenTab = nil
        }

        let webView = try XCTUnwrap(
            tab.ensureUntrackedNormalWebView(reason: "SafariExtensionWebViewControllerWiringTests")
        )
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            manager.ensureExtensionController(for: profile.id)
        )
        XCTAssertEqual(
            didOpenCount,
            0,
            "ensureUntrackedNormalWebView must not notify extensions before initial-document context warmup"
        )

        await fulfillment(of: [didOpenExpectation], timeout: 3.0)
        XCTAssertEqual(didOpenCount, 1)
        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertTrue(tab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)
        XCTAssertEqual(tab.extensionPageRuntimeOwner.openNotifiedContextReadiness, .loaded)

        await manager.drainExtensionRuntimeTasksForTests()
        webView.stopLoading()
    }

    func testVisibleTabSelectionDefersInitialWebViewCreationUntilNativeMessagingWarmup()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            initialProfileProvider: { profile }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = WebViewCoordinator()
        browserManager.tabManager = TabManager(
            runtimePorts: BrowserTabManagerRuntimePortsFactory.registry(for: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Work",
            profileId: profile.id
        )
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let scratchDirectory = try makeScratchDirectory()
        let manager = try XCTUnwrap(extensionsModule.managerIfEnabled())
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)
        manager.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        manager.extensionsLoaded = true

        var backgroundWakeCount = 0
        let backgroundWakeExpectation = expectation(
            description: "nativeMessaging warmup before WebView creation"
        )
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
            backgroundWakeExpectation.fulfill()
        }
        defer {
            manager.testHooks.backgroundContentWake = nil
        }

        let pageURL = URL(string: "https://example.com/login")!
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: pageURL.absoluteString,
            in: space,
            activate: false
        )
        tab.profileId = profile.id
        windowState.currentTabId = tab.id

        let coordinator = try XCTUnwrap(browserManager.webViewCoordinator)
        XCTAssertTrue(
            extensionsModule.needsInitialDocumentExtensionContextLoadIfNeeded(
                profileId: profile.id
            )
        )
        browserManager.selectTab(tab, in: windowState, loadPolicy: .immediate)
        XCTAssertNil(tab.resolvedCurrentWebView())
        XCTAssertNil(coordinator.getWebView(for: tab.id, in: windowState.id))

        await fulfillment(of: [backgroundWakeExpectation], timeout: 3.0)
        XCTAssertEqual(backgroundWakeCount, 1)
        XCTAssertEqual(
            manager.backgroundRuntimeState(for: installed.id, profileId: profile.id),
            .loaded
        )

        var createdWebView: WKWebView?
        for _ in 0..<20 {
            await Task.yield()
            createdWebView = coordinator.getOrCreateWebView(
                for: tab,
                in: windowState.id
            )
            if createdWebView != nil {
                break
            }
        }
        let webView = try XCTUnwrap(createdWebView)
        XCTAssertIdentical(tab.resolvedCurrentWebView(), webView)
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            manager.ensureExtensionController(for: profile.id)
        )
    }

    func testExtensionRequestedInternalTabUsesContextConfigurationAndStaysRuntimeOwned() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Page Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        browserManager.tabManager = TabManager(
            runtimePorts: BrowserTabManagerRuntimePortsFactory.registry(for: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Work",
            profileId: profile.id
        )
        manager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), manager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedPage"
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)

        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            manager.extensionControllersByProfile[profile.id]
        )
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        let tab = try manager.openExtensionRequestedTab(
            url: extensionURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(tab.url, extensionURL)
        XCTAssertEqual(tab.spaceId, space.id)
        XCTAssertIdentical(
            tab.webExtensionContextOverride,
            extensionContext,
            "Extension-created internal tabs must keep the matching context for WebKit page configuration"
        )
        XCTAssertFalse(
            browserManager.tabManager.structuralPersistence.shouldPersistRegularTab(tab),
            "Extension-created internal tabs are runtime-owned, not browser session tabs"
        )
        XCTAssertNil(browserManager.tabManager.structuralPersistence.persistableCurrentTabID())
    }

    func testExtensionRequestedBackgroundInternalTabMaterializesWithContext() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Background Extension Page Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        browserManager.tabManager = TabManager(
            runtimePorts: BrowserTabManagerRuntimePortsFactory.registry(for: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Work",
            profileId: profile.id
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedBackgroundPage"
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)

        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            manager.extensionControllersByProfile[profile.id]
        )
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        let tab = try manager.openExtensionRequestedTab(
            url: extensionURL,
            shouldBeActive: false,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(tab.webExtensionContextOverride, extensionContext)
        XCTAssertTrue(browserManager.tabManager.transientWebKitTabLifecycleOwner.isTransientExtensionTab(tab))
        XCTAssertIdentical(browserManager.tabManager.tabCollectionMembershipOwner.tab(for: tab.id), tab)
        XCTAssertFalse(
            browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.contains(where: { $0.id == tab.id }) ?? false,
            "Inactive internal extension pages should not appear in the visible regular tab list"
        )
        XCTAssertFalse(
            tab.isUnloaded,
            "Background extension-created internal tabs must not stay browser-discarded"
        )
        let webView = try XCTUnwrap(tab.resolvedCurrentWebView())
        XCTAssertIdentical(webView.configuration.webExtensionController, controller)

        let metrics = try await pollExtensionRenderMetrics(in: webView)
        XCTAssertTrue(metrics.loadedFromExtensionScheme, metrics.debugSummary)
        XCTAssertEqual(metrics.readyState, "complete", metrics.debugSummary)
        XCTAssertGreaterThan(metrics.elementCount, 0, metrics.debugSummary)
        XCTAssertGreaterThan(metrics.scriptCount, 0, metrics.debugSummary)
        XCTAssertEqual(metrics.marker, "rendered", metrics.debugSummary)
        XCTAssertFalse(browserManager.tabManager.structuralPersistence.shouldPersistRegularTab(tab))

        let adapter = try XCTUnwrap(manager.adapterResolutionOwner.stableAdapter(for: tab))
        let closed = expectation(description: "transient extension tab closed")
        var closeError: Error?
        adapter.close(for: extensionContext) { error in
            closeError = error
            closed.fulfill()
        }
        await fulfillment(of: [closed], timeout: 1.0)
        XCTAssertNil(closeError)
        XCTAssertNil(browserManager.tabManager.tabCollectionMembershipOwner.tab(for: tab.id))
        XCTAssertFalse(browserManager.tabManager.transientWebKitTabLifecycleOwner.isTransientExtensionTab(tab))
        XCTAssertFalse(
            browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.contains(where: { $0.id == tab.id }) ?? false
        )
    }

    func testExtensionTabAdapterActivateWithoutWindowContextReturnsError() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Activation Error Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true
        manager.tabOpenNotificationGeneration = 11

        let browserManager = makeBrowserManager(profile: profile)
        browserManager.webViewCoordinator = WebViewCoordinator()
        browserManager.tabManager = TabManager(
            runtimePorts: BrowserTabManagerRuntimePortsFactory.registry(for: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        let visibleSpace = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Visible",
            profileId: profile.id
        )
        let hiddenSpace = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Hidden",
            profileId: profile.id
        )
        let selectedTab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/selected",
            in: visibleSpace,
            activate: true
        )
        let targetTab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/hidden",
            in: hiddenSpace,
            activate: false
        )
        targetTab.profileId = profile.id
        targetTab.extensionPageRuntimeOwner.eligibleGeneration = manager.tabOpenNotificationGeneration

        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = visibleSpace.id
        windowState.currentTabId = selectedTab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        manager.attach(browserManager: browserManager)

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        let adapter = try XCTUnwrap(manager.adapterResolutionOwner.stableAdapter(for: targetTab))
        let activation = expectation(description: "hidden extension tab activation rejected")
        var activationError: NSError?
        adapter.activate(for: extensionContext) { error in
            activationError = error as NSError?
            activation.fulfill()
        }
        await fulfillment(of: [activation], timeout: 1.0)

        XCTAssertNotNil(activationError)
        XCTAssertEqual(
            activationError?.localizedDescription,
            "No browser window is available for this tab"
        )
        XCTAssertEqual(windowState.currentTabId, selectedTab.id)
        XCTAssertEqual(browserManager.tabManager.selectionStateOwner.currentTab?.id, selectedTab.id)
    }

    func testExtensionRequestedSafariURLUsesNativeWebKitContext() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Page Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        browserManager.tabManager = TabManager(
            runtimePorts: BrowserTabManagerRuntimePortsFactory.registry(for: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        _ = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Work",
            profileId: profile.id
        )
        manager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), manager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedPublicURLPage"
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)

        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            manager.extensionControllersByProfile[profile.id]
        )
        XCTAssertEqual(extensionContext.baseURL.scheme, "safari-web-extension")
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        let tab = try manager.openExtensionRequestedTab(
            url: extensionURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(tab.url, extensionURL)
        XCTAssertIdentical(controller.extensionContext(for: tab.url), extensionContext)
        XCTAssertIdentical(
            tab.webExtensionContextOverride,
            extensionContext,
            "Safari-public extension URLs must be loaded through the matching WebKit context"
        )
        XCTAssertFalse(browserManager.tabManager.structuralPersistence.shouldPersistRegularTab(tab))
    }

    func testExtensionRequestedWindowTabUsesContextConfigurationAndRuntimeLifecycle() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Window Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = WebViewCoordinator()
        browserManager.tabManager = TabManager(
            runtimePorts: BrowserTabManagerRuntimePortsFactory.registry(for: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Work",
            profileId: profile.id
        )
        manager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), manager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedWindowPage"
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)

        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            manager.extensionControllersByProfile[profile.id]
        )
        XCTAssertEqual(extensionContext.baseURL.scheme, "safari-web-extension")
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        var openedTabIDs: [UUID] = []
        manager.testHooks.didOpenTab = { openedTabIDs.append($0) }
        let openedWindow = expectation(description: "extension window opened")
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?

        manager.openExtensionWindowUsingTabURLs(
            [extensionURL],
            controller: controller,
            createWindow: {
                let windowState = BrowserWindowState()
                windowState.currentProfileId = profile.id
                windowState.currentSpaceId = space.id
                windowRegistry.register(windowState)
                windowRegistry.setActive(windowState)
            },
            awaitWindowRegistration: { existingWindowIDs in
                await windowRegistry.awaitNextRegisteredWindow(
                    excluding: existingWindowIDs
                )
            },
            completionHandler: { window, error in
                completionWindow = window
                completionError = error
                openedWindow.fulfill()
            }
        )

        await fulfillment(of: [openedWindow], timeout: 2.0)
        XCTAssertNil(completionError)
        XCTAssertNotNil(completionWindow)

        let tab = try XCTUnwrap(
            browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.first(where: {
                $0.url == extensionURL
            })
        )
        XCTAssertEqual(openedTabIDs.filter { $0 == tab.id }.count, 1)
        XCTAssertIdentical(controller.extensionContext(for: tab.url), extensionContext)
        XCTAssertIdentical(
            tab.webExtensionContextOverride,
            extensionContext
        )
        XCTAssertFalse(browserManager.tabManager.structuralPersistence.shouldPersistRegularTab(tab))
    }

    func testExtensionRequestedInternalTabRendersThroughSumiWebViewPath() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Render Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        browserManager.tabManager = TabManager(
            runtimePorts: BrowserTabManagerRuntimePortsFactory.registry(for: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        _ = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Work",
            profileId: profile.id
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedRenderedPage"
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)

        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            manager.extensionControllersByProfile[profile.id]
        )
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        let tab = try manager.openExtensionRequestedTab(
            url: extensionURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = try XCTUnwrap(
            tab.ensureUntrackedNormalWebView(
                reason: "SafariExtensionWebViewControllerWiringTests.extensionRender"
            )
        )

        let metrics = try await pollExtensionRenderMetrics(in: webView)
        XCTAssertTrue(metrics.loadedFromExtensionScheme, metrics.debugSummary)
        XCTAssertEqual(metrics.readyState, "complete", metrics.debugSummary)
        XCTAssertGreaterThan(metrics.elementCount, 0, metrics.debugSummary)
        XCTAssertGreaterThan(metrics.scriptCount, 0, metrics.debugSummary)
        XCTAssertEqual(metrics.marker, "rendered", metrics.debugSummary)
        XCTAssertIdentical(webView.configuration.webExtensionController, controller)
        XCTAssertIdentical(
            webView.configuration.websiteDataStore,
            controller.configuration.defaultWebsiteDataStore
        )
    }

    func testExtensionOptionsPageRendersThroughContextConfiguration() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Options Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionOptionsRenderedPage",
            optionsPage: "options.html"
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)

        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            manager.extensionControllersByProfile[profile.id]
        )

        let openedOptions = expectation(description: "options page opened")
        var completionError: Error?
        manager.presentOptionsPageWindow(for: extensionContext) { error in
            completionError = error
            openedOptions.fulfill()
        }
        await fulfillment(of: [openedOptions], timeout: 2.0)
        XCTAssertNil(completionError)

        let window = try XCTUnwrap(manager.optionsWindows[installed.id])
        let contentView = try XCTUnwrap(window.contentView)
        let webView = try XCTUnwrap(Self.firstWebView(in: contentView))

        let metrics = try await pollExtensionRenderMetrics(in: webView)
        XCTAssertTrue(metrics.loadedFromExtensionScheme, metrics.debugSummary)
        XCTAssertEqual(metrics.readyState, "complete", metrics.debugSummary)
        XCTAssertGreaterThan(metrics.elementCount, 0, metrics.debugSummary)
        XCTAssertGreaterThan(metrics.scriptCount, 0, metrics.debugSummary)
        XCTAssertEqual(metrics.marker, "rendered", metrics.debugSummary)
        XCTAssertIdentical(webView.configuration.webExtensionController, controller)
        XCTAssertIdentical(
            webView.configuration.websiteDataStore,
            controller.configuration.defaultWebsiteDataStore
        )
    }

    func testExtensionRequestedInternalTabIsNotRenotifiedOnCommitOrActivation() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Page Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        browserManager.tabManager = TabManager(
            runtimePorts: BrowserTabManagerRuntimePortsFactory.registry(for: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        _ = browserManager.tabManager.spaceLifecycleOwner.createSpace(
            name: "Work",
            profileId: profile.id
        )
        manager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), manager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedPage"
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)

        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            manager.extensionControllersByProfile[profile.id]
        )
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        var didOpenCount = 0
        manager.testHooks.didOpenTab = { tabID in
            if browserManager.tabManager.tabCollectionMembershipOwner.tab(for: tabID)?.url == extensionURL {
                didOpenCount += 1
            }
        }

        let tab = try manager.openExtensionRequestedTab(
            url: extensionURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(didOpenCount, 1)

        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: extensionURL)
        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests.didCommit"
        )
        manager.notifyTabActivated(newTab: tab, previous: nil)

        XCTAssertEqual(
            didOpenCount,
            1,
            "Commit and activation callbacks must not duplicate the extension-created internal tab"
        )
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.lastOpenNotificationGeneration,
            manager.tabOpenNotificationGeneration
        )
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence,
            tab.extensionPageRuntimeOwner.documentSequence - 1,
            "The delegate-created tab stays open-notified for the original extension page instance"
        )
    }

    func testMarkTabEligibleAfterCommittedNavigationNotifiesTabOpened() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true
        manager.tabOpenNotificationGeneration = 9

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        let didOpenExpectation = expectation(description: "didOpenTab")
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                didOpenExpectation.fulfill()
            }
        }

        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        wait(for: [didOpenExpectation], timeout: 2)
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.lastOpenNotificationGeneration,
            manager.tabOpenNotificationGeneration
        )
        XCTAssertTrue(tab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)
    }

    func testMarkTabEligibleAfterCommittedNavigationDoesNotNotifyTwice() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true
        manager.tabOpenNotificationGeneration = 11

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        var notifyCount = 0
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                notifyCount += 1
            }
        }

        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests.first"
        )
        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests.second"
        )

        XCTAssertEqual(notifyCount, 1)
    }

    func testMarkTabEligibleAfterCommittedNavigationEnablesExtensionWebView() async throws {
        let server = try await AutofillPagesHTTPServer.start()
        addTeardownBlock {
            server.stop()
        }

        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        let expectedController = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let pageURL = server.loginBasicURL
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )

        let didFinish = expectation(description: "page loaded")
        let delegate = AutofillPagesNavigationDelegateBox {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.load(URLRequest(url: pageURL, cachePolicy: .reloadIgnoringLocalCacheData))
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil

        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
        XCTAssertNotNil(
            manager.extensionWebView(for: tab, extensionContext: extensionContext)
        )
    }

    private final class AutofillPagesNavigationDelegateBox: NSObject, WKNavigationDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            onFinish()
        }
    }

}
