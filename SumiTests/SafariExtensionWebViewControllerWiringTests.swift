import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionWebViewControllerWiringTests: XCTestCase {
    private func makeManager(
        context: ModelContext,
        profile: Profile,
        browserConfiguration: BrowserConfiguration = BrowserConfiguration()
    ) -> (manager: ExtensionManager, browserConfiguration: BrowserConfiguration) {
        SafariExtensionLiveWebKitTestLease.holdForProcess()
        let manager = makeSafariExtensionTestExtensionManager(
            context: context,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        return (manager, browserConfiguration)
    }

    private func makeBrowserManager(
        moduleRegistry: SumiModuleRegistry? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        profile: Profile? = nil
    ) -> BrowserManager {
        let browserManager = makeSafariExtensionTestBrowserManager(
            moduleRegistry: moduleRegistry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        return browserManager
    }

    @discardableResult
    private func attachUsableExtensionWebView(
        to tab: Tab,
        manager: ExtensionManager,
        profile: Profile
    ) -> WKWebView {
        let configuration = manager.browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView
        return webView
    }

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
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        XCTAssertTrue(manager.attachExtensionControllerIfNeeded(to: webView, for: tab))
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
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

        XCTAssertTrue(delegateObject === manager)
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
        tab._webView = webView
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
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

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
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profileB.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(profileId: profileB.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

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
        tab.browserManager = browserManager
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

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
        tab.browserManager = browserManager
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

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

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.profileId = profile.id
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        let adapter = try XCTUnwrap(manager.stableAdapter(for: tab))
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
        extensionsModule.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let manager = try XCTUnwrap(extensionsModule.managerIfEnabled())
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "WebViewWiringExtension"
        )
        _ = try await manager.enableExtension(installed.id)
        manager.extensionsLoaded = true

        let tab = browserManager.tabManager.createNewTab(
            url: "about:blank",
            in: browserManager.tabManager.currentSpace,
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
        extensionsModule.attach(browserManager: browserManager)
        browserManager.tabManager = TabManager(
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
            name: "Work",
            profileId: profile.id
        )

        let scratchDirectory = try makeScratchDirectory()
        let manager = try XCTUnwrap(extensionsModule.managerIfEnabled())
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        manager.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        manager.extensionsLoaded = true

        XCTAssertFalse(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))

        let pageURL = URL(string: "https://example.com/login")!
        let tab = browserManager.tabManager.createNewTab(
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

        let webView = try XCTUnwrap(tab.ensureWebView())
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            manager.ensureExtensionController(for: profile.id)
        )
        XCTAssertEqual(
            didOpenCount,
            0,
            "Tab.setupWebView must not notify extensions before initial-document context warmup"
        )

        await fulfillment(of: [didOpenExpectation], timeout: 3.0)
        XCTAssertEqual(didOpenCount, 1)
        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertTrue(tab.didNotifyOpenToExtensions)
        XCTAssertEqual(tab.extensionRuntimeOpenNotifiedWithLoadedContexts, true)

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
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
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
        _ = try await manager.enableExtension(installed.id)
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
        let tab = browserManager.tabManager.createNewTab(
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
        XCTAssertNil(tab.existingWebView)
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
        XCTAssertIdentical(tab.existingWebView, webView)
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
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
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
        _ = try await manager.enableExtension(installed.id)

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
            browserManager.tabManager.shouldPersistRegularTab(tab),
            "Extension-created internal tabs are runtime-owned, not browser session tabs"
        )
        XCTAssertNil(browserManager.tabManager.persistableCurrentTabID())
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
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
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
        _ = try await manager.enableExtension(installed.id)

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
        XCTAssertTrue(browserManager.tabManager.isTransientExtensionTab(tab))
        XCTAssertIdentical(browserManager.tabManager.tab(for: tab.id), tab)
        XCTAssertFalse(
            browserManager.tabManager.tabsBySpace[space.id]?.contains(where: { $0.id == tab.id }) ?? false,
            "Inactive internal extension pages should not appear in the visible regular tab list"
        )
        XCTAssertFalse(
            tab.isUnloaded,
            "Background extension-created internal tabs must not stay browser-discarded"
        )
        let webView = try XCTUnwrap(tab.existingWebView)
        XCTAssertIdentical(webView.configuration.webExtensionController, controller)

        let metrics = try await pollExtensionRenderMetrics(in: webView)
        XCTAssertTrue(metrics.loadedFromExtensionScheme, metrics.debugSummary)
        XCTAssertEqual(metrics.readyState, "complete", metrics.debugSummary)
        XCTAssertGreaterThan(metrics.elementCount, 0, metrics.debugSummary)
        XCTAssertGreaterThan(metrics.scriptCount, 0, metrics.debugSummary)
        XCTAssertEqual(metrics.marker, "rendered", metrics.debugSummary)
        XCTAssertFalse(browserManager.tabManager.shouldPersistRegularTab(tab))

        let adapter = try XCTUnwrap(manager.stableAdapter(for: tab))
        let closed = expectation(description: "transient extension tab closed")
        var closeError: Error?
        adapter.close(for: extensionContext) { error in
            closeError = error
            closed.fulfill()
        }
        await fulfillment(of: [closed], timeout: 1.0)
        XCTAssertNil(closeError)
        XCTAssertNil(browserManager.tabManager.tab(for: tab.id))
        XCTAssertFalse(browserManager.tabManager.isTransientExtensionTab(tab))
        XCTAssertFalse(
            browserManager.tabManager.tabsBySpace[space.id]?.contains(where: { $0.id == tab.id }) ?? false
        )
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
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        _ = browserManager.tabManager.createSpace(
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
        _ = try await manager.enableExtension(installed.id)

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
        XCTAssertFalse(browserManager.tabManager.shouldPersistRegularTab(tab))
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
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
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
        _ = try await manager.enableExtension(installed.id)

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
            browserManager.tabManager.tabsBySpace[space.id]?.first(where: {
                $0.url == extensionURL
            })
        )
        XCTAssertEqual(openedTabIDs.filter { $0 == tab.id }.count, 1)
        XCTAssertIdentical(controller.extensionContext(for: tab.url), extensionContext)
        XCTAssertIdentical(
            tab.webExtensionContextOverride,
            extensionContext
        )
        XCTAssertFalse(browserManager.tabManager.shouldPersistRegularTab(tab))
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
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        _ = browserManager.tabManager.createSpace(
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
        _ = try await manager.enableExtension(installed.id)

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
        let webView = try XCTUnwrap(tab.ensureWebView())

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
        _ = try await manager.enableExtension(installed.id)

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
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        _ = browserManager.tabManager.createSpace(
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
        _ = try await manager.enableExtension(installed.id)

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
            if browserManager.tabManager.tab(for: tabID)?.url == extensionURL {
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

        tab.noteCommittedMainDocumentNavigation(to: extensionURL)
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
            tab.lastExtensionOpenNotificationGeneration,
            manager.tabOpenNotificationGeneration
        )
        XCTAssertEqual(
            tab.extensionRuntimeOpenNotifiedDocumentSequence,
            tab.extensionRuntimeDocumentSequence - 1,
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
        tab.browserManager = browserManager

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

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
            tab.lastExtensionOpenNotificationGeneration,
            manager.tabOpenNotificationGeneration
        )
        XCTAssertTrue(tab.didNotifyOpenToExtensions)
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
        tab.browserManager = browserManager

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

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
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.browserManager = browserManager
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

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

    func testTabNeedsExtensionContentScriptRebindWhenContextsWereNotLoadedAtNotify() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.extensionRuntimeOpenNotifiedWithLoadedContexts = false
        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testNotifyTabOpenedDefersUntilContentScriptContextsLoad() async throws {
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

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        manager.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "http://127.0.0.1:8765/login-basic.html")!
        )
        tab.browserManager = browserManager
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

        XCTAssertFalse(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertFalse(manager.notifyTabOpened(tab))
        let deferredTask = manager.deferredTabNotificationTask(for: tab.id)

        await manager.ensureContentScriptContextsLoaded(for: profile.id)
        await deferredTask?.value
        attachUsableExtensionWebView(
            to: tab,
            manager: manager,
            profile: profile
        )
        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertTrue(manager.notifyTabOpened(tab))
        XCTAssertEqual(tab.extensionRuntimeOpenNotifiedWithLoadedContexts, true)
    }

    func testNotifyTabOpenedDefersUntilInitialDocumentNativeMessagingWarmup() async throws {
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

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        let entity = try XCTUnwrap(try manager.extensionEntity(for: installed.id))
        entity.isEnabled = true
        try container.mainContext.save()
        _ = manager.loadInstalledExtensionMetadata()

        await manager.ensureContentScriptContextsLoaded(for: profile.id)

        var backgroundWakeCount = 0
        var backgroundWakeKey: String?
        var backgroundWakeObservations: [String] = []
        let backgroundWakeExpectation = expectation(description: "nativeMessaging warmup")
        backgroundWakeExpectation.assertForOverFulfill = false
        manager.testHooks.backgroundContentWake = { wakeKey, extensionContext in
            backgroundWakeKey = wakeKey
            let contextIdentity = manager.contextIdentity(for: extensionContext)
            let stateBefore = manager.backgroundRuntimeState(
                for: installed.id,
                profileId: profile.id
            )
            backgroundWakeObservations.append(
                "wake=\(backgroundWakeCount + 1) key=\(wakeKey) expectedProfile=\(profile.id) contextProfile=\(contextIdentity?.profileId.uuidString ?? "nil") stateBefore=\(stateBefore)"
            )
            backgroundWakeCount += 1
            backgroundWakeExpectation.fulfill()
        }
        defer {
            manager.testHooks.backgroundContentWake = nil
        }

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://example.com/login")!
        )
        tab.browserManager = browserManager
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration
        attachUsableExtensionWebView(
            to: tab,
            manager: manager,
            profile: profile
        )

        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertTrue(manager.profileNeedsInitialDocumentNativeMessagingWarmup(profileId: profile.id))
        XCTAssertFalse(manager.notifyTabOpened(tab))
        XCTAssertFalse(tab.didNotifyOpenToExtensions)

        await fulfillment(of: [backgroundWakeExpectation], timeout: 3.0)
        if let deferredTask = manager.deferredTabNotificationTask(for: tab.id) {
            await deferredTask.value
        }
        XCTAssertEqual(backgroundWakeCount, 1, backgroundWakeObservations.joined(separator: "\n"))
        XCTAssertEqual(
            backgroundWakeKey,
            manager.backgroundScopedKey(
                extensionId: installed.id,
                profileId: profile.id
            )
        )
        XCTAssertEqual(
            manager.backgroundRuntimeState(for: installed.id, profileId: profile.id),
            .loaded
        )
    }

    func testNotifyTabOpenedDefersUntilLiveWebViewExists() async throws {
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

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        await manager.ensureContentScriptContextsLoaded(for: profile.id)

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://example.com/login")!
        )
        tab.browserManager = browserManager
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertFalse(manager.notifyTabOpened(tab))
        XCTAssertFalse(tab.didNotifyOpenToExtensions)

        attachUsableExtensionWebView(
            to: tab,
            manager: manager,
            profile: profile
        )

        XCTAssertTrue(manager.notifyTabOpened(tab))
        XCTAssertEqual(tab.extensionRuntimeOpenNotifiedWithLoadedContexts, true)
    }

    func testUserGestureReconcileDoesNotRebuildLivePageForMissedContentScriptBinding()
        async throws {
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

        let browserManager = makeBrowserManager(profile: profile)
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = WebViewCoordinator()
        browserManager.tabManager = TabManager(
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
            name: "Work",
            profileId: profile.id
        )
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        await manager.ensureContentScriptContextsLoaded(for: profile.id)

        let pageURL = URL(string: "https://example.com/login")!
        let tab = browserManager.tabManager.createNewTab(
            url: pageURL.absoluteString,
            in: space,
            activate: false
        )
        tab.profileId = profile.id
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration
        let webView = attachUsableExtensionWebView(
            to: tab,
            manager: manager,
            profile: profile
        )
        tab.assignWebViewToWindow(webView, windowId: windowState.id)
        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
        let webViewBeforeGesture = try XCTUnwrap(tab.existingWebView)

        manager.reconcileExtensionRuntimeOnUserGestureIfNeeded(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(tab.existingWebView, webViewBeforeGesture)
    }

    func testExtensionRequestedNormalTabPreloadsContentScriptContextsBeforeOpenNotification() async throws {
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
        let controller = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true

        let browserManager = makeBrowserManager(profile: profile)
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = WebViewCoordinator()
        browserManager.tabManager = TabManager(
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
            name: "Work",
            profileId: profile.id
        )
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        manager.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )

        let pageURL = URL(string: "https://example.com/login")!
        XCTAssertFalse(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))

        let preparedProfileId = try await manager.prepareExtensionRequestedTabForInitialLoad(
            url: pageURL,
            requestedWindow: nil,
            controller: controller
        )

        XCTAssertEqual(preparedProfileId, profile.id)
        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))

        var openedTabIDs: [UUID] = []
        var deferredOpenReasons: [String] = []
        manager.testHooks.didOpenTab = { openedTabIDs.append($0) }
        manager.testHooks.didDeferOpenTab = { _, reason in
            deferredOpenReasons.append(reason)
        }
        defer { manager.clearDebugState() }

        let tab = try manager.openExtensionRequestedTab(
            url: pageURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(tab.url, pageURL)
        XCTAssertEqual(tab.spaceId, space.id)
        XCTAssertNil(tab.webViewConfigurationOverride)
        XCTAssertNotNil(tab.assignedWebView ?? tab.existingWebView)
        XCTAssertEqual(
            openedTabIDs.filter { $0 == tab.id }.count,
            1,
            "deferredOpenReasons=\(deferredOpenReasons)"
        )
        XCTAssertEqual(
            tab.extensionRuntimeOpenNotifiedWithLoadedContexts,
            true,
            "deferredOpenReasons=\(deferredOpenReasons)"
        )
        XCTAssertTrue(tab.didNotifyOpenToExtensions)
    }

    func testExtensionRequestedNormalTabDoesNotWakeNativeMessagingBackgrounds() async throws {
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
        let controller = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true

        let browserManager = makeBrowserManager(profile: profile)
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = WebViewCoordinator()
        browserManager.tabManager = TabManager(
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
            name: "Work",
            profileId: profile.id
        )
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        let entity = try XCTUnwrap(try manager.extensionEntity(for: installed.id))
        entity.isEnabled = true
        try container.mainContext.save()
        _ = manager.loadInstalledExtensionMetadata()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }
        defer {
            manager.testHooks.backgroundContentWake = nil
        }

        let pageURL = URL(string: "https://example.com/login")!
        XCTAssertFalse(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))

        let preparedProfileId = try await manager.prepareExtensionRequestedTabForInitialLoad(
            url: pageURL,
            requestedWindow: nil,
            controller: controller
        )

        XCTAssertEqual(preparedProfileId, profile.id)
        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertTrue(manager.profileNeedsInitialDocumentNativeMessagingWarmup(profileId: profile.id))
        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            manager.backgroundRuntimeState(for: installed.id, profileId: profile.id),
            .neverLoaded
        )

        _ = try manager.openExtensionRequestedTab(
            url: pageURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            manager.backgroundRuntimeState(for: installed.id, profileId: profile.id),
            .neverLoaded
        )
    }

    func testExtensionRequestedNormalWindowPreloadsContentScriptContextsBeforeOpenNotification() async throws {
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
        let controller = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true

        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
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
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
            name: "Work",
            profileId: profile.id
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        manager.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )

        let pageURL = URL(string: "https://example.com/login")!
        XCTAssertFalse(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))

        var openedTabIDs: [UUID] = []
        var deferredOpenReasons: [String] = []
        manager.testHooks.didOpenTab = { openedTabIDs.append($0) }
        manager.testHooks.didDeferOpenTab = { _, reason in
            deferredOpenReasons.append(reason)
        }
        defer { manager.clearDebugState() }
        let openedWindow = expectation(description: "extension normal window opened")
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?

        manager.openExtensionWindowUsingTabURLs(
            [pageURL],
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
        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))

        let tab = try XCTUnwrap(
            browserManager.tabManager.allTabs().first { $0.url == pageURL }
        )
        XCTAssertNotNil(tab.assignedWebView ?? tab.existingWebView)
        XCTAssertEqual(
            openedTabIDs.count,
            1,
            "deferredOpenReasons=\(deferredOpenReasons)"
        )
        XCTAssertEqual(
            tab.extensionRuntimeOpenNotifiedWithLoadedContexts,
            true,
            "deferredOpenReasons=\(deferredOpenReasons)"
        )
        XCTAssertTrue(tab.didNotifyOpenToExtensions)
    }

    func testLazyContentScriptContextLoadDoesNotWakeBackgroundForOrdinaryNavigation() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptBackgroundProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )

        let entity = try XCTUnwrap(try manager.extensionEntity(for: installed.id))
        entity.isEnabled = true
        try container.mainContext.save()
        _ = manager.loadInstalledExtensionMetadata()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }

        await manager.ensureContentScriptContextsLoaded(for: profile.id)

        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            manager.backgroundRuntimeState(for: installed.id, profileId: profile.id),
            .neverLoaded
        )

        manager.extensionsLoaded = true
        manager.tabOpenNotificationGeneration = 17
        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        manager.prepareExtensionRuntimeBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: pageURL,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            manager.backgroundRuntimeState(for: installed.id, profileId: profile.id),
            .neverLoaded
        )
    }

    func testDeferredTabNotificationWaitsForInitialDocumentNativeMessagingWarmup() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )

        let entity = try XCTUnwrap(try manager.extensionEntity(for: installed.id))
        entity.isEnabled = true
        try container.mainContext.save()
        _ = manager.loadInstalledExtensionMetadata()

        var backgroundWakeCount = 0
        let backgroundWakeExpectation = expectation(description: "nativeMessaging background wake")
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
            backgroundWakeExpectation.fulfill()
        }

        await manager.ensureContentScriptContextsLoaded(for: profile.id)

        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            manager.backgroundRuntimeState(for: installed.id, profileId: profile.id),
            .neverLoaded
        )
        XCTAssertTrue(
            manager.profileNeedsInitialDocumentNativeMessagingWarmup(profileId: profile.id)
        )
        XCTAssertTrue(
            manager.profileNeedsInitialDocumentExtensionContextLoad(profileId: profile.id)
        )

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        defer {
            manager.testHooks.backgroundContentWake = nil
        }

        manager.scheduleDeferredTabNotificationAfterContextLoad(
            tab,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let deferredTask = manager.deferredTabNotificationTask(for: tab.id)

        await fulfillment(of: [backgroundWakeExpectation], timeout: 3.0)
        await deferredTask?.value

        XCTAssertEqual(backgroundWakeCount, 1)
        XCTAssertEqual(
            manager.backgroundRuntimeState(for: installed.id, profileId: profile.id),
            .loaded
        )
    }

    func testInitialDocumentWarmupDoesNotWakeBackgroundWithoutNativeMessaging() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptBackgroundProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )

        let entity = try XCTUnwrap(try manager.extensionEntity(for: installed.id))
        entity.isEnabled = true
        try container.mainContext.save()
        _ = manager.loadInstalledExtensionMetadata()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }

        await manager.ensureInitialDocumentExtensionContextsLoaded(for: profile.id)

        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            manager.backgroundRuntimeState(for: installed.id, profileId: profile.id),
            .neverLoaded
        )
    }

    func testInitialDocumentWarmupWakesBackgroundForNativeMessagingContentScripts() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )

        let entity = try XCTUnwrap(try manager.extensionEntity(for: installed.id))
        entity.isEnabled = true
        try container.mainContext.save()
        _ = manager.loadInstalledExtensionMetadata()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }

        await manager.ensureInitialDocumentExtensionContextsLoaded(for: profile.id)

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let nativeMessagingPermission = WKWebExtension.Permission(rawValue: "nativeMessaging")
        XCTAssertTrue(context.isLoaded)
        XCTAssertTrue(
            manager.isGrantedPermissionStatus(
                context.permissionStatus(for: nativeMessagingPermission)
            )
        )
        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertEqual(backgroundWakeCount, 1)
        XCTAssertEqual(
            manager.backgroundRuntimeState(for: installed.id, profileId: profile.id),
            .loaded
        )
        XCTAssertEqual(
            manager.runtimeMetricsByExtensionID[
                manager.backgroundScopedKey(
                    extensionId: installed.id,
                    profileId: profile.id
                )
            ]?.lastBackgroundWakeReason,
            .nativeMessaging
        )
    }

    func testRuntimeTeardownInvalidatesLoadBeforeControllerLoad() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "TeardownRaceProbe"
        )
        let entity = try XCTUnwrap(try manager.extensionEntity(for: installed.id))
        entity.isEnabled = true
        try container.mainContext.save()
        let controller = manager.ensureExtensionController(for: profile.id)

        manager.testHooks.beforeControllerLoad = { _, _ in
            manager.tearDownExtensionRuntime(
                reason: "SafariExtensionWebViewControllerWiringTests",
                removeUIState: true,
                releaseController: true
            )
        }

        do {
            _ = try await manager.loadEnabledExtension(from: entity)
            XCTFail("A load invalidated by runtime teardown must not reach WebKit")
        } catch {
            XCTAssertTrue(error is CancellationError, String(describing: error))
        }

        XCTAssertTrue(controller.extensionContexts.isEmpty)
        XCTAssertTrue(manager.extensionContextsByProfile.isEmpty)
        XCTAssertTrue(manager.extensionControllersByProfile.isEmpty)
    }

    func testRuntimeTeardownUnloadsLoadedContexts() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        let controller = try XCTUnwrap(extensionContext.webExtensionController)

        XCTAssertTrue(extensionContext.isLoaded)
        XCTAssertFalse(controller.extensionContexts.isEmpty)

        manager.tearDownExtensionRuntime(
            reason: "SafariExtensionWebViewControllerWiringTests",
            removeUIState: true,
            releaseController: true
        )

        XCTAssertFalse(extensionContext.isLoaded)
        XCTAssertTrue(controller.extensionContexts.isEmpty)
        XCTAssertTrue(manager.extensionContextsByProfile.isEmpty)
        XCTAssertTrue(manager.extensionControllersByProfile.isEmpty)
    }

    func testUserExtensionRuntimeTeardownMarksAllLiveNormalTabsAffected()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)
        browserManager.tabManager = TabManager(
            browserManager: browserManager,
            context: container.mainContext,
            loadPersistedState: false
        )
        let space = browserManager.tabManager.createSpace(
            name: "Work",
            profileId: profile.id
        )
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        _ = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        manager.extensionsLoaded = true

        let tabWithController = browserManager.tabManager.createNewTab(
            url: "https://example.com/with-controller",
            in: space,
            activate: false
        )
        tabWithController.profileId = profile.id
        let controllerConfiguration = browserConfiguration
            .auxiliaryWebViewConfiguration(surface: .extensionOptions)
        manager.prepareWebViewConfigurationForExtensionRuntime(
            controllerConfiguration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webViewWithController = FocusableWKWebView(
            frame: .zero,
            configuration: controllerConfiguration
        )
        webViewWithController.owningTab = tabWithController
        tabWithController._webView = webViewWithController

        let tabWithoutController = browserManager.tabManager.createNewTab(
            url: "https://example.com/without-controller",
            in: space,
            activate: false
        )
        tabWithoutController.profileId = profile.id
        let plainConfiguration = browserConfiguration
            .auxiliaryWebViewConfiguration(surface: .extensionOptions)
        let webViewWithoutController = FocusableWKWebView(
            frame: .zero,
            configuration: plainConfiguration
        )
        webViewWithoutController.owningTab = tabWithoutController
        tabWithoutController._webView = webViewWithoutController

        let affectedIDs = Set(
            manager.tabsAffectedByLoadedUserExtensionRuntime().map(\.id)
        )

        XCTAssertTrue(manager.hasLoadedUserExtensionRuntime)
        XCTAssertTrue(affectedIDs.contains(tabWithController.id))
        XCTAssertTrue(affectedIDs.contains(tabWithoutController.id))
    }

    func testRuntimeTeardownClearsTabExtensionOverridesBeforeRebuild() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true,
            profileId: profile.id
        )
        manager.extensionsLoaded = true

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://accounts.google.com/")!
        )
        let webView = attachUsableExtensionWebView(
            to: tab,
            manager: manager,
            profile: profile
        )
        tab.webViewConfigurationOverride = webView.configuration
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 1
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 1
        tab.extensionRuntimeOpenNotifiedWithLoadedContexts = true

        XCTAssertNotNil(webView.configuration.webExtensionController)
        XCTAssertNotNil(tab.webViewConfigurationOverride)

        manager.rebuildLiveWebViewsAfterUserExtensionRuntimeTeardown(
            [tab],
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertNil(tab.webViewConfigurationOverride)
        XCTAssertNil(tab.extensionRuntimeOpenNotifiedDocumentSequence)
        XCTAssertNil(tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration)
        XCTAssertNil(tab.extensionRuntimeOpenNotifiedWithLoadedContexts)
    }

    func testTabNeedsExtensionContentScriptRebindWhenOpenNotifiedAfterCommit() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "http://127.0.0.1:8765/login-basic.html")!
        )
        tab.noteCommittedMainDocumentNavigation(to: tab.url)
        tab.extensionRuntimeOpenNotifiedDocumentSequence = tab.extensionRuntimeDocumentSequence

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testTabDoesNotNeedExtensionContentScriptRebindWhenOpenPrecededCommit() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "http://127.0.0.1:8765/login-basic.html")!
        )
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: tab.url)

        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testTabNeedsExtensionContentScriptRebindAfterReloadCommitWithoutWillStartNotification() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))

        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testPrepareExtensionRuntimeBeforeNavigationReNotifiesOnReload() throws {
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
        manager.tabOpenNotificationGeneration = 21

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.browserManager = browserManager

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)
        tab.lastExtensionOpenNotificationGeneration = manager.tabOpenNotificationGeneration
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))

        let didCloseExpectation = expectation(description: "didCloseTab before reload commit")
        let didOpenExpectation = expectation(description: "didOpenTab before reload commit")
        manager.testHooks.didCloseTab = { tabID in
            if tabID == tab.id {
                didCloseExpectation.fulfill()
            }
        }
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                didOpenExpectation.fulfill()
            }
        }

        manager.prepareExtensionRuntimeBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: pageURL,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        wait(for: [didCloseExpectation, didOpenExpectation], timeout: 2)
        XCTAssertEqual(tab.extensionRuntimeOpenNotifiedDocumentSequence, tab.extensionRuntimeDocumentSequence)
        XCTAssertEqual(
            tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration,
            manager.extensionContextBindingGeneration(for: profile.id)
        )

        tab.noteCommittedMainDocumentNavigation(to: pageURL)
        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testPrepareBeforeNavigationCyclesCloseOpenOnReload() throws {
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
        let controller = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true
        _ = controller

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.browserManager = browserManager
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration
        attachUsableExtensionWebView(
            to: tab,
            manager: manager,
            profile: profile
        )

        let didCloseExpectation = expectation(description: "didCloseTab before reload commit")
        let didOpenExpectation = expectation(description: "didOpenTab before reload commit")
        manager.testHooks.didCloseTab = { tabID in
            if tabID == tab.id {
                didCloseExpectation.fulfill()
            }
        }
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                didOpenExpectation.fulfill()
            }
        }

        manager.prepareExtensionRuntimeBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: pageURL,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        wait(for: [didCloseExpectation, didOpenExpectation], timeout: 2)
    }

    func testTabNeedsRebindWhenExtensionContextBindingChanges() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))

        manager.bumpExtensionContextBindingGeneration(
            for: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testWrongControllerTriggersContentScriptRebind() throws {
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
        let controllerA = manager.ensureExtensionController(for: profileA.id)
        let controllerB = manager.ensureExtensionController(for: profileB.id)

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profileA.id, url: pageURL)
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        configuration.webExtensionController = controllerB
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: pageURL))
        tab._webView = webView

        XCTAssertTrue(manager.webViewNeedsExtensionRuntimeRebuild(webView, for: tab))
        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
        _ = controllerA
    }

    func testContentScriptProbeExtensionDeclaresManifestCSS() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        let manifestURL = URL(fileURLWithPath: installed.packagePath)
            .appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let contentScripts = manifest?["content_scripts"] as? [[String: Any]]
        let css = contentScripts?.first?["css"] as? [String]
        XCTAssertEqual(css, ["overlay.css"])
        XCTAssertTrue(
            ((manifest?["web_accessible_resources"] as? [[String: Any]])?.first?["resources"] as? [String])?
                .contains("overlay.html") == true
        )
    }

    func testConfigureContextIdentityKeepsPublicIdentifierAndScopesBaseURL() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let otherProfile = Profile(name: "Profile B")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        let extensionId = "probe-extension-id"
        let scratchDirectory = try makeScratchDirectory()
        let directoryURL = scratchDirectory.appendingPathComponent("BaseURLProbe", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Probe",
            "version": "1.0",
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])

        let webExtension = try await WKWebExtension(resourceBaseURL: directoryURL)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let otherExtensionContext = WKWebExtensionContext(for: webExtension)
        manager.configureContextIdentity(
            extensionContext,
            extensionId: extensionId,
            profileId: profile.id
        )
        manager.configureContextIdentity(
            otherExtensionContext,
            extensionId: extensionId,
            profileId: otherProfile.id
        )

        let baseURL = try XCTUnwrap(extensionContext.baseURL)
        let otherBaseURL = try XCTUnwrap(otherExtensionContext.baseURL)
        XCTAssertEqual(extensionContext.uniqueIdentifier, extensionId)
        XCTAssertEqual(otherExtensionContext.uniqueIdentifier, extensionId)
        XCTAssertEqual(baseURL.scheme, "safari-web-extension")
        XCTAssertTrue(baseURL.host?.hasPrefix("ext-") == true)
        XCTAssertNotEqual(baseURL.host, otherBaseURL.host)
    }

    func testPrepareWebViewForExtensionRuntimeAttachesControllerOnBlankWebView() throws {
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
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab

        manager.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: URL(string: "about:blank"),
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
    }

    private func makeTab(profileId: UUID, url: URL) -> Tab {
        let tab = Tab(url: url, name: "Test")
        tab.profileId = profileId
        return tab
    }

    private func makeLoadedExtensionContext(
        manager: ExtensionManager,
        profile: Profile
    ) async throws -> WKWebExtensionContext {
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ContextProbeExtension"
        )
        _ = try await manager.enableExtension(installed.id)
        let context = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        return try XCTUnwrap(context)
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func pollExtensionRenderMetrics(
        in webView: WKWebView
    ) async throws -> ExtensionRenderMetrics {
        var lastMetrics = ExtensionRenderMetrics.empty
        for _ in 0..<80 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let metrics = try? await extensionRenderMetrics(in: webView) {
                lastMetrics = metrics
                if metrics.readyState == "complete",
                   metrics.loadedFromExtensionScheme,
                   metrics.elementCount > 0,
                   metrics.scriptCount > 0 {
                    return metrics
                }
            }
        }

        XCTFail("Timed out waiting for Sumi-created extension page; \(lastMetrics.debugSummary)")
        return lastMetrics
    }

    private func extensionRenderMetrics(
        in webView: WKWebView
    ) async throws -> ExtensionRenderMetrics {
        let script = """
            (() => [
              document.readyState,
              document.querySelectorAll('body *').length,
              document.scripts.length,
              document.body ? (document.body.dataset.sumiRenderMarker || '') : '',
              location.href.startsWith('safari-web-extension://')
            ].join('|'))();
            """
        let rawValue = try await webView.evaluateJavaScript(script) as? String
        return try ExtensionRenderMetrics(rawValue: rawValue ?? "")
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

    private func installContentScriptProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "ContentScriptCSSProbe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "ContentScriptCSSProbe",
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "css": ["overlay.css"],
                "run_at": "document_idle",
            ]],
            "web_accessible_resources": [[
                "resources": ["overlay.html"],
                "matches": ["<all_urls>"],
            ]],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])
        try Data("true;".utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])
        try Data("iframe{height:1px;}".utf8)
            .write(to: directoryURL.appendingPathComponent("overlay.css"), options: [.atomic])
        try Data("<!doctype html><title>overlay</title>".utf8)
            .write(to: directoryURL.appendingPathComponent("overlay.html"), options: [.atomic])

        return try await manager.performInstallation(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    private func installContentScriptBackgroundProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "ContentScriptBackgroundProbe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "ContentScriptBackgroundProbe",
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "background": [
                "service_worker": "background.js",
            ],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "run_at": "document_idle",
            ]],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])
        try Data("true;".utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])
        try Data("globalThis.__sumiBackgroundProbe = true;".utf8)
            .write(to: directoryURL.appendingPathComponent("background.js"), options: [.atomic])

        return try await manager.performInstallation(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    private func installContentScriptNativeMessagingProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "ContentScriptNativeMessagingProbe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "ContentScriptNativeMessagingProbe",
            "version": "1.0",
            "permissions": ["nativeMessaging"],
            "host_permissions": ["<all_urls>"],
            "background": [
                "service_worker": "background.js",
            ],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "run_at": "document_start",
            ]],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])
        try Data("browser.runtime.sendMessage({kind:'probe'});".utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])
        try Data("globalThis.__sumiNativeMessagingBackgroundProbe = true;".utf8)
            .write(to: directoryURL.appendingPathComponent("background.js"), options: [.atomic])

        return try await manager.performInstallation(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    private func installUnpackedExtension(
        manager: ExtensionManager,
        scratchDirectory: URL,
        name: String,
        optionsPage: String? = nil
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "action": ["default_popup": "popup.html"],
        ]
        if let optionsPage {
            manifest["options_ui"] = ["page": optionsPage]
        }
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(to: manifestURL, options: [.atomic])
        try Data(
            """
            <!doctype html>
            <title>popup</title>
            <main id="ready">Loaded</main>
            <script src="popup.js"></script>
            """.utf8
        )
            .write(to: directoryURL.appendingPathComponent("popup.html"), options: [.atomic])
        if let optionsPage {
            try Data(
                """
                <!doctype html>
                <title>options</title>
                <main id="ready">Loaded</main>
                <script src="popup.js"></script>
                """.utf8
            )
                .write(to: directoryURL.appendingPathComponent(optionsPage), options: [.atomic])
        }
        try Data(
            """
            document.body.dataset.sumiRenderMarker = 'rendered';
            """.utf8
        )
            .write(to: directoryURL.appendingPathComponent("popup.js"), options: [.atomic])

        return try await manager.performInstallation(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    private static func firstWebView(in root: NSView) -> WKWebView? {
        if let webView = root as? WKWebView {
            return webView
        }
        for subview in root.subviews {
            if let webView = firstWebView(in: subview) {
                return webView
            }
        }
        return nil
    }
}

private struct ExtensionRenderMetrics: Equatable {
    var readyState: String
    var elementCount: Int
    var scriptCount: Int
    var marker: String
    var loadedFromExtensionScheme: Bool

    static let empty = ExtensionRenderMetrics(
        readyState: "",
        elementCount: 0,
        scriptCount: 0,
        marker: "",
        loadedFromExtensionScheme: false
    )

    var debugSummary: String {
        [
            "ready=\(readyState)",
            "elements=\(elementCount)",
            "scripts=\(scriptCount)",
            "marker=\(marker)",
            "extensionScheme=\(loadedFromExtensionScheme)",
        ].joined(separator: " ")
    }

    init(
        readyState: String,
        elementCount: Int,
        scriptCount: Int,
        marker: String,
        loadedFromExtensionScheme: Bool
    ) {
        self.readyState = readyState
        self.elementCount = elementCount
        self.scriptCount = scriptCount
        self.marker = marker
        self.loadedFromExtensionScheme = loadedFromExtensionScheme
    }

    init(rawValue: String) throws {
        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 5,
              let elements = Int(parts[1]),
              let scripts = Int(parts[2])
        else {
            throw NSError(
                domain: "SafariExtensionWebViewControllerWiringTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid render metrics"]
            )
        }

        readyState = String(parts[0])
        elementCount = elements
        scriptCount = scripts
        marker = String(parts[3])
        loadedFromExtensionScheme = parts[4] == "true"
    }
}
