import AppKit
import SumiWebRuntime
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
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        let expectedController = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "about:blank")!,
            browserManager: browserManager
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        XCTAssertTrue(
            attachedRuntime.runtime.controller.admission.admit(
                expectedController,
                profileID: profile.id,
                to: webView,
                for: tab
            ).isUsable
        )
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
    }

    func testExtensionRuntimeLiveLookupPrefersWindowOwnedTrackedWebView() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let windowRegistry = WindowRegistry()
        let browserManager = makeBrowserManager(
            profile: profile,
            windowRegistry: windowRegistry
        )
        let trackedAdmission = browserManager.webViewRuntime.trackedWebViewAdmission
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        manager.attach(browserManager: browserManager)

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://example.com")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        windowState.currentTabId = tab.id
        let staleWebView = WKWebView()
        let trackedWebView = FocusableWKWebView()
        trackedWebView.owningTab = tab
        tab.replaceUntrackedWebView(staleWebView)
        trackedAdmission.registerAuxiliaryTrackedWebView(
            trackedWebView,
            for: tab,
            in: windowState.id
        )

        XCTAssertIdentical(
            attachedRuntime.runtime.controller.webViews.liveWebView(for: tab),
            trackedWebView
        )
        let liveWebViews = managerFixture.attachedRuntime.runtime.bridge.webViews
            .extensionLiveWebViews(for: tab)
        XCTAssertEqual(liveWebViews.count, 1)
        XCTAssertIdentical(liveWebViews.first, trackedWebView)
    }

    func testProfileExtensionControllerUsesSumiNativeMessagingDelegate() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let controller = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
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

        XCTAssertTrue(delegateObject === inspection.controller.delegateBridge)
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
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        _ = inspection.controller.provisioning.ensureExtensionController(for: profile.id)

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
            inspection: inspection,
            profile: profile
        )
        XCTAssertTrue(extensionContext.isLoaded)
        XCTAssertFalse(attachedRuntime.hasInstalledRuntime)
        XCTAssertNil(webView.configuration.webExtensionController)
    }

    func testColdInstallActivationDoesNotMaterializeBrowserRuntime() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Cold install activation")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            inspection: inspection,
            profile: profile
        )

        let extensionID = try XCTUnwrap(inspection.contextState.profiles.extensionId(for: extensionContext))
        let claim = inspection.contextCoordination.loads.begin(
            for: .init(profileId: profile.id, extensionId: extensionID)
        )
        defer { _ = inspection.contextCoordination.loads.finishIfCurrent(claim) }
        let receipt = try XCTUnwrap(
            inspection.contextState.profiles.contextBindingReceipt(
                extensionId: extensionID,
                profileId: profile.id
            )
        )
        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controller(ifCurrent: receipt)
        )
        try await inspection.installation.runtimeActivation.activate(
            .init(
                loadedContext: .init(
                    context: extensionContext,
                    controller: controller,
                    bindingReceipt: receipt,
                    loadClaim: claim,
                    mutationLease: nil
                ),
                installedExtensionId: extensionID,
                operation: .install
            )
        )

        XCTAssertTrue(extensionContext.isLoaded)
        XCTAssertFalse(attachedRuntime.hasInstalledRuntime)
    }

    func testWebViewBindingPolicyRequiresControllerBeforeCreation() {
        let expected = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        XCTAssertFalse(
            ExtensionRuntimeWebViewBindingPolicy.needsRuntimeRebuild(
                currentController: expected,
                expectedController: expected
            )
        )
        XCTAssertTrue(
            ExtensionRuntimeWebViewBindingPolicy.needsRuntimeRebuild(
                currentController: nil,
                expectedController: expected
            )
        )
        XCTAssertFalse(
            ExtensionRuntimeWebViewBindingPolicy.needsRuntimeRebuild(
                currentController: nil,
                expectedController: nil
            )
        )
    }

    func testExtensionWebViewReturnsProfileMatchedController() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        let expectedController = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "about:blank")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            inspection: inspection,
            profile: profile
        )
        let resolvedWebView = try XCTUnwrap(
            attachedRuntime.runtime.controller.tabWebViewResolver.extensionWebView(
                for: tab,
                extensionContext: extensionContext
            )
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
        let managerFixture = makeManager(
            context: container,
            profile: profileA,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let browserManager = makeBrowserManager(profile: profileA)
        manager.attach(browserManager: browserManager)
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
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
            inspection: inspection,
            profile: profileA
        )
        XCTAssertNil(
            attachedRuntime.runtime.controller.tabWebViewResolver.extensionWebView(
                for: tab,
                extensionContext: extensionContext
            )
        )
    }

    func testIsTabEligibleForCurrentExtensionRuntimeBlocksEphemeralTabs() throws {
        let container = try makeTestContainer()
        let ephemeralProfile = Profile.createEphemeral()
        let managerFixture = makeManager(
            context: container,
            profile: ephemeralProfile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime

        let browserManager = makeBrowserManager(profile: ephemeralProfile)
        manager.attach(browserManager: browserManager)

        let tab = makeTab(
            profileId: ephemeralProfile.id,
            url: URL(string: "https://example.com")!,
            browserManager: browserManager
        )
        tab.extensionPageRuntimeOwner.markEligible(for: inspection.runtimeAuthorities.tabPublicationRevisions.issue())

        XCTAssertTrue(ephemeralProfile.isEphemeral)
        XCTAssertTrue(tab.isEphemeral)
        XCTAssertFalse(
            managerFixture.attachedRuntime.runtime.normalTabs.preparedTabs
                .containsPreparedTab(tab)
        )
    }

    func testNotifyTabActivatedSkipsGenerationEligibleEphemeralTabs() throws {
        let container = try makeTestContainer()
        let ephemeralProfile = Profile.createEphemeral()
        let managerFixture = makeManager(
            context: container,
            profile: ephemeralProfile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        _ = inspection.controller.provisioning.ensureExtensionController(for: ephemeralProfile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let browserManager = makeBrowserManager(profile: ephemeralProfile)
        manager.attach(browserManager: browserManager)

        let tab = makeTab(
            profileId: ephemeralProfile.id,
            url: URL(string: "https://example.com")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.extensionPageRuntimeOwner.markEligible(for: inspection.runtimeAuthorities.tabPublicationRevisions.issue())

        var activatedTabIDs: [UUID] = []
        manager.testHooks.didActivateTab = { activatedTabIDs.append($0) }

        XCTAssertTrue(tab.isEphemeral)
        managerFixture.attachedRuntime.runtime.publications.tabActivation
            .activate(tab, previous: nil)

        XCTAssertTrue(activatedTabIDs.isEmpty)
    }

    func testExtensionTabAdapterDoesNotReturnWebViewWithoutController() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        _ = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com",
            in: browserManager.spaceStateOwner.currentSpace,
            activate: false
        )
        tab.profileId = profile.id
        tab.extensionPageRuntimeOwner.markEligible(for: inspection.runtimeAuthorities.tabPublicationRevisions.issue())

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            inspection: inspection,
            profile: profile
        )
        let adapter = try XCTUnwrap(
            managerFixture.attachedRuntime.runtime.adapters.stableAdapter(
                for: tab
            )
        )
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
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            moduleRegistry: registry
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        extensionsModule.attach(runtime: BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager))

        let scratchDirectory = try makeScratchDirectory()
        XCTAssertIdentical(extensionsModule.managerForTesting(), manager)
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "WebViewWiringExtension"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "about:blank",
            in: browserManager.spaceStateOwner.currentSpace,
            activate: false
        )
        tab.profileId = profile.id

        let webView = try XCTUnwrap(tab.makeNormalTabWebView(reason: "SafariExtensionWebViewControllerWiringTests"))
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            inspection.controller.provisioning.ensureExtensionController(for: profile.id)
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
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            moduleRegistry: registry
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        extensionsModule.attach(runtime: BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager))
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )

        let scratchDirectory = try makeScratchDirectory()
        XCTAssertIdentical(extensionsModule.managerForTesting(), manager)
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        inspection.contextCoordination.residency.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        XCTAssertFalse(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )

        let pageURL = URL(string: "https://example.com/login")!
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: pageURL.absoluteString,
            in: space,
            activate: false
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        registerWindowDisplaying(
            tab,
            profileId: profile.id,
            browserManager: browserManager
        )
        inspection.browserPublication.reloads.reloadLoadedRuntime(
            reason: #function,
            profileID: profile.id
        )

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
            inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        )
        XCTAssertEqual(
            didOpenCount,
            0,
            "ensureUntrackedNormalWebView must not notify extensions before initial-document context warmup"
        )

        await fulfillment(of: [didOpenExpectation], timeout: 3.0)
        XCTAssertEqual(didOpenCount, 1)
        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )
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
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            moduleRegistry: registry
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let windowRegistry = WindowRegistry()
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile,
            windowRegistry: windowRegistry
        )
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let scratchDirectory = try makeScratchDirectory()
        XCTAssertIdentical(extensionsModule.managerForTesting(), manager)
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        inspection.contextCoordination.residency.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

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
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: pageURL.absoluteString,
            in: space,
            activate: false
        )
        tab.profileId = profile.id
        windowState.currentTabId = tab.id

        let webViewQuery = browserManager.webViewRuntime.ownershipQuery
        let webViewMaterialization = browserManager.webViewRuntime.trackedWebViewAdmission
        XCTAssertTrue(
            extensionsModule.needsInitialDocumentExtensionContextLoadIfNeeded(
                profileId: profile.id
            )
        )
        browserManager.selectTab(tab, in: windowState, loadPolicy: .immediate)
        XCTAssertNil(tab.resolvedCurrentWebView())
        XCTAssertNil(webViewQuery.webView(for: tab.id, in: windowState.id))

        await fulfillment(of: [backgroundWakeExpectation], timeout: 3.0)
        XCTAssertEqual(backgroundWakeCount, 1)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .loaded
        )

        var createdWebView: WKWebView?
        for _ in 0..<20 {
            await Task.yield()
            createdWebView = webViewMaterialization.webView(
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
            inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        )
    }

    func testExtensionRequestedInternalTabUsesContextConfigurationAndStaysRuntimeOwned() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Page Profile")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedPage"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)

        let loadedContext = try await inspection.contextCoordination.residency.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controllersByProfile[profile.id]
        )
        publishNormalExtensionWindow(
            inspection: inspection,
            browserManager: browserManager,
            profile: profile
        )
        let evidence = try XCTUnwrap(
            inspection.controller.callbackAdmission.capture(
                context: extensionContext,
                controller: controller
            )
        )
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        let tab = try managerFixture.attachedRuntime.runtime.requestedTabs
            .opening.open(
            url: extensionURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            extensionContext: extensionContext,
            evidence: evidence,
            callbackAdmission: inspection.controller.callbackAdmission,
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
            browserManager.structuralPersistence.shouldPersistRegularTab(tab),
            "Extension-created internal tabs are runtime-owned, not browser session tabs"
        )
        XCTAssertNil(browserManager.structuralPersistence.persistableCurrentTabID())
    }

    func testExtensionRequestedBackgroundInternalTabMaterializesWithContext() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Background Extension Page Profile")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedBackgroundPage"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)

        let loadedContext = try await inspection.contextCoordination.residency.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controllersByProfile[profile.id]
        )
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        let tab = try managerFixture.attachedRuntime.runtime.requestedTabs
            .opening.open(
            url: extensionURL,
            shouldBeActive: false,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            extensionContext: extensionContext,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(tab.webExtensionContextOverride, extensionContext)
        XCTAssertTrue(browserManager.extensionTabCommands.containsTransient(tab))
        XCTAssertIdentical(browserManager.tabCollectionMembershipOwner.tab(for: tab.id), tab)
        XCTAssertFalse(
            browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.contains(where: { $0.id == tab.id }) ?? false,
            "Inactive internal extension pages should not appear in the visible regular tab list"
        )
        XCTAssertFalse(
            tab.isUnloaded,
            "Background extension-created internal tabs must not stay browser-discarded"
        )
        let webView = try XCTUnwrap(tab.resolvedCurrentWebView())
        XCTAssertIdentical(webView.configuration.webExtensionController, controller)

        let metrics = try await awaitExtensionRenderMetrics(in: webView)
        XCTAssertTrue(metrics.loadedFromExtensionScheme, metrics.debugSummary)
        XCTAssertEqual(metrics.readyState, "complete", metrics.debugSummary)
        XCTAssertGreaterThan(metrics.elementCount, 0, metrics.debugSummary)
        XCTAssertGreaterThan(metrics.scriptCount, 0, metrics.debugSummary)
        XCTAssertEqual(metrics.marker, "rendered", metrics.debugSummary)
        XCTAssertFalse(browserManager.structuralPersistence.shouldPersistRegularTab(tab))

        let adapter = try XCTUnwrap(
            managerFixture.attachedRuntime.runtime.adapters.stableAdapter(
                for: tab
            )
        )
        let closed = expectation(description: "transient extension tab closed")
        var closeError: Error?
        adapter.close(for: extensionContext) { error in
            closeError = error
            closed.fulfill()
        }
        await fulfillment(of: [closed], timeout: 1.0)
        XCTAssertNil(closeError)
        XCTAssertNil(browserManager.tabCollectionMembershipOwner.tab(for: tab.id))
        XCTAssertFalse(browserManager.extensionTabCommands.containsTransient(tab))
        XCTAssertFalse(
            browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.contains(where: { $0.id == tab.id }) ?? false
        )
    }

    func testExtensionTabAdapterActivateWithoutWindowContextReturnsError() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Activation Error Profile")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        _ = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let windowRegistry = WindowRegistry()
        let browserManager = makeBrowserManager(
            profile: profile,
            windowRegistry: windowRegistry
        )
        let visibleSpace = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Visible",
            profileID: profile.id
        )
        let hiddenSpace = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Hidden",
            profileID: profile.id
        )
        let selectedTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/selected",
            in: visibleSpace,
            activate: true
        )
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = visibleSpace.id
        windowState.currentTabId = selectedTab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        manager.attach(browserManager: browserManager)

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            inspection: inspection,
            profile: profile
        )
        let targetTab = browserManager.extensionTabCommands
            .createTransient(
                url: try XCTUnwrap(URL(string: "safari-web-extension://activation-error/hidden.html")),
                in: hiddenSpace,
                webExtensionContextOverride: extensionContext
            )
        targetTab.profileId = profile.id
        targetTab.extensionPageRuntimeOwner.markEligible(
            for: inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        )
        let adapter = try XCTUnwrap(
            managerFixture.attachedRuntime.runtime.adapters.stableAdapter(
                for: targetTab
            )
        )
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
        XCTAssertEqual(browserManager.tabStateStore.selection.currentTab?.id, selectedTab.id)
    }

    func testExtensionTabAdapterReloadCreatesTabOwnedSemanticCommand() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Reload Profile")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        _ = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionReloadSemanticCommand"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        let loadedContext = try await inspection.contextCoordination.residency.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controllersByProfile[profile.id]
        )
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")
        let tab = try managerFixture.attachedRuntime.runtime.requestedTabs
            .opening.open(
            url: extensionURL,
            shouldBeActive: false,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            extensionContext: extensionContext,
            reason: "SafariExtensionWebViewControllerWiringTests.reload"
        )
        let adapter = try XCTUnwrap(
            managerFixture.attachedRuntime.runtime.adapters.stableAdapter(
                for: tab
            )
        )
        let previousNavigationIntent = try XCTUnwrap(
            tab.mainFrameLoads.currentIntent(matching: extensionURL)
        )
        let previousRebuildRevision = tab.webViewRebuildEpoch.current

        let reloaded = expectation(description: "extension tab reload accepted")
        var reloadError: NSError?
        adapter.reload(fromOrigin: true, for: extensionContext) { error in
            reloadError = error as NSError?
            reloaded.fulfill()
        }
        await fulfillment(of: [reloaded], timeout: 1.0)

        XCTAssertNil(reloadError)
        let currentNavigationIntent = try XCTUnwrap(
            tab.mainFrameLoads.currentIntent(matching: extensionURL)
        )
        XCTAssertGreaterThan(
            currentNavigationIntent.revision,
            previousNavigationIntent.revision,
            "WebExtension reload must enter the same Tab-owned semantic revision pipeline as browser reload"
        )
        XCTAssertGreaterThan(
            tab.webViewRebuildEpoch.current,
            previousRebuildRevision
        )
    }

    func testExtensionRequestedSafariURLUsesNativeWebKitContext() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Page Profile")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        _ = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        manager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerForTesting(), manager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedPublicURLPage"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)

        let loadedContext = try await inspection.contextCoordination.residency.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controllersByProfile[profile.id]
        )
        publishNormalExtensionWindow(
            inspection: inspection,
            browserManager: browserManager,
            profile: profile
        )
        let evidence = try XCTUnwrap(
            inspection.controller.callbackAdmission.capture(
                context: extensionContext,
                controller: controller
            )
        )
        XCTAssertEqual(extensionContext.baseURL.scheme, "safari-web-extension")
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        let tab = try managerFixture.attachedRuntime.runtime.requestedTabs
            .opening.open(
            url: extensionURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            extensionContext: extensionContext,
            evidence: evidence,
            callbackAdmission: inspection.controller.callbackAdmission,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(tab.url, extensionURL)
        XCTAssertIdentical(controller.extensionContext(for: tab.url), extensionContext)
        XCTAssertIdentical(
            tab.webExtensionContextOverride,
            extensionContext,
            "Safari-public extension URLs must be loaded through the matching WebKit context"
        )
        XCTAssertFalse(browserManager.structuralPersistence.shouldPersistRegularTab(tab))
    }

    func testExtensionRequestedWindowPublishesAllInitialTabsBeforeFocusAndCompletion() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Window Profile")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let windowRegistry = WindowRegistry()
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile,
            windowRegistry: windowRegistry
        )
        browserManager.windowShellContentViewFactory = { _, _ in NSView() }
        let windowSessions = browserManager.windowSessionBundle
        BrowserWindowRegistryBinding.install(
            registration: windowSessions.restoration,
            closing: BrowserWindowCloseWorkflow(
                browserRuntime: browserManager,
                recorder: windowSessions.history.recorder,
                persistence: browserManager.windowSessionPersistenceCoordinator,
                extensions: browserManager.optionalModules.extensions,
                webViews: browserManager.webViewRuntime.lifecycleService,
                emptySplitPlaceholders: browserManager.splitEmptyPlaceholders,
                splitPreviews: browserManager.splitWindowContext.previews,
                backgroundMedia: browserManager
                    .backgroundMediaOptimizationService,
                commands: browserManager.windowCommands
            ),
            activity: browserManager.windowActivation,
            allWindowsClosed: BrowserAllWindowsClosedWorkflow(
                browserRuntime: browserManager,
                sessionRestore: windowSessions.restoreService,
                siteDataPolicy: browserManager.dataServices
                    .siteDataPolicyEnforcementService,
                profiles: browserManager.profileManager
            ),
            on: windowRegistry
        )
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        manager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerForTesting(), manager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedWindowPage"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)

        let loadedContext = try await inspection.contextCoordination.residency.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controllersByProfile[profile.id]
        )
        XCTAssertEqual(extensionContext.baseURL.scheme, "safari-web-extension")
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")
        let externalURL = URL(string: "https://example.com/second")!
        let requestedFrame = CGRect(x: 160, y: 180, width: 720, height: 520)

        let preexistingWindowIDs = Set(windowRegistry.windows.keys)
        var openedTabIDs: [UUID] = []
        var closedTabIDs: [UUID] = []
        var windowWasPublishedBeforeTab = false
        manager.testHooks.didOpenTab = { tabID in
            openedTabIDs.append(tabID)
            windowWasPublishedBeforeTab = extensionContext.openWindows
                .contains { $0 is ExtensionWindowAdapter }
        }
        manager.testHooks.didCloseTab = { closedTabIDs.append($0) }
        let openedWindow = expectation(description: "extension window opened")
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?
        var tabWasPublishedBeforeCompletion = false
        var windowWasFocusedBeforeCompletion = false

        attachedRuntime.runtime.requestedTabs.windowRouter.open(
            request: ExtensionWindowOpeningRequest(
                windowType: .normal,
                frame: requestedFrame,
                tabURLs: [extensionURL, externalURL],
                shouldBeFocused: true,
                shouldBePrivate: false
            ),
            controller: controller,
            extensionContext: extensionContext,
            completion: { window, error in
                completionWindow = window
                completionError = error
                tabWasPublishedBeforeCompletion = openedTabIDs.count == 2
                if let adapter = window as? ExtensionWindowAdapter {
                    windowWasFocusedBeforeCompletion =
                        (extensionContext.focusedWindow as? ExtensionWindowAdapter)
                        === adapter
                }
                openedWindow.fulfill()
            }
        )

        await fulfillment(of: [openedWindow], timeout: 2.0)
        XCTAssertNil(
            completionError,
            "openedTabs=\(openedTabIDs.count) closedTabs=\(closedTabIDs.count) registeredWindows=\(windowRegistry.windows.count) contextWindows=\(extensionContext.openWindows.count)"
        )
        let adapter = try XCTUnwrap(
            completionWindow as? ExtensionWindowAdapter
        )
        XCTAssertTrue(windowWasPublishedBeforeTab)
        XCTAssertTrue(tabWasPublishedBeforeCompletion)
        XCTAssertTrue(windowWasFocusedBeforeCompletion)

        let tab = try XCTUnwrap(
            browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.first(where: {
                $0.url == extensionURL
            })
        )
        XCTAssertEqual(openedTabIDs.filter { $0 == tab.id }.count, 1)
        let externalTab = try XCTUnwrap(
            browserManager.tabStateStore.regularTabs
                .tabsBySpaceSnapshot()[space.id]?.first(where: {
                    $0.url == externalURL
                })
        )
        XCTAssertEqual(openedTabIDs.filter { $0 == externalTab.id }.count, 1)
        XCTAssertIdentical(controller.extensionContext(for: tab.url), extensionContext)
        XCTAssertIdentical(
            tab.webExtensionContextOverride,
            extensionContext
        )
        let window = try XCTUnwrap(windowRegistry.windows[adapter.windowId])
        XCTAssertEqual(adapter.tabs(for: extensionContext).count, 2)
        XCTAssertFalse(preexistingWindowIDs.contains(window.id))
        XCTAssertEqual(window.currentProfileId, profile.id)
        XCTAssertEqual(window.currentSpaceId, space.id)
        XCTAssertEqual(window.currentTabId, tab.id)
        let webView = try XCTUnwrap(
            browserManager.webViewRuntime.ownershipQuery.webView(
                for: tab.id,
                in: window.id
            ) as? FocusableWKWebView
        )
        XCTAssertIdentical(webView.owningTab, tab)
        XCTAssertEqual(
            browserManager.webViewRuntime.ownershipQuery.trackedOwner(
                containing: webView
            ),
            TrackedWebViewOwner(tabID: tab.id, windowID: window.id)
        )
        XCTAssertIdentical(
            managerFixture.attachedRuntime.runtime.publications
                .windowPublications.publishedWindowAdapter(
                for: window,
                profileID: profile.id
            ),
            adapter
        )
        XCTAssertTrue(
            windowRegistry.appKitWindow(for: window)?.isVisible == true
        )
        XCTAssertEqual(
            windowRegistry.appKitWindow(for: window)?.frame,
            requestedFrame
        )
        XCTAssertFalse(browserManager.structuralPersistence.shouldPersistRegularTab(tab))
        XCTAssertTrue(
            browserManager.structuralPersistence
                .shouldPersistRegularTab(externalTab)
        )
        let appKitWindow = windowRegistry.appKitWindow(for: window)
        windowRegistry.unregister(window.id)
        appKitWindow?.close()
    }

    func testExtensionRequestedWindowCancelsBeforePresentationWhenPublishedAdapterIsMissing() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Requested Window Rollback")
        let browserConfiguration = BrowserConfiguration()
        let requestedWindowManagerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = requestedWindowManagerFixture.manager
        let inspection = requestedWindowManagerFixture.inspection
        let attachedRuntime = requestedWindowManagerFixture.attachedRuntime
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let windowRegistry = WindowRegistry()
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile,
            windowRegistry: windowRegistry
        )
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        manager.attach(browserManager: browserManager)
        let controller = inspection.controller.provisioning.ensureExtensionController(for: profile.id)

        let prepared = RequestedWindowPreparedStub()
        let creator = RequestedWindowCreatorStub(prepared: prepared)
        let router = makeWindowRequestRouter(
            inspection: inspection,
            attachedRuntime:
                requestedWindowManagerFixture.attachedRuntime.runtime,
            windowCreation: creator
        )
        let originalWindowIDs = Set(windowRegistry.windows.keys)
        let originalTabIDs = Set(
            browserManager.tabCollectionMembershipOwner
                .allTabs().map(\.id)
        )
        let completed = expectation(description: "missing adapter rejected")
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?

        router.open(
            tabURLs: [URL(string: "about:blank")!],
            controller: controller,
            extensionContext: nil,
            completion: { window, error in
                completionWindow = window
                completionError = error
                completed.fulfill()
            }
        )

        await fulfillment(of: [completed], timeout: 2.0)
        XCTAssertNil(completionWindow)
        XCTAssertEqual(
            (completionError as NSError?)?.code,
            ExtensionManagerCallbackError.newWindowUnavailable.code
        )
        XCTAssertEqual(creator.preparedSeeds.count, 1)
        XCTAssertIdentical(creator.preparedSeeds.first?.space, space)
        XCTAssertEqual(creator.preparedSeeds.first?.profileID, profile.id)
        XCTAssertEqual(prepared.presentCallCount, 0)
        XCTAssertEqual(prepared.acceptCallCount, 0)
        XCTAssertEqual(prepared.cancelCallCount, 1)
        XCTAssertEqual(Set(windowRegistry.windows.keys), originalWindowIDs)
        XCTAssertEqual(
            Set(
                browserManager.tabCollectionMembershipOwner
                    .allTabs().map(\.id)
            ),
            originalTabIDs
        )
    }

    func testColdExtensionRequestedWindowFailsWithoutMaterializingBrowserRuntime()
        throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Cold requested window")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let controller = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        var callbackCount = 0
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?

        inspection.normalTabs.requestedTabs.openWindow(
            tabURLs: [URL(string: "https://example.com")!],
            controller: controller,
            extensionContext: nil,
            completion: { window, error in
                callbackCount += 1
                completionWindow = window
                completionError = error
            }
        )

        XCTAssertEqual(callbackCount, 1)
        XCTAssertNil(completionWindow)
        XCTAssertEqual(
            (completionError as NSError?)?.code,
            ExtensionManagerCallbackError.browserManagerUnavailable.code
        )
        XCTAssertFalse(attachedRuntime.hasInstalledRuntime)
    }

    func testReleasedBrowserAttachmentRejectsReloadAndWindowRequest() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Released browser attachment")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        var browserManager: BrowserManager? = makeSafariExtensionTestBrowserManager(
            profile: profile,
            automaticallyStartPersistedStateLoad: false,
            retainUntilTestTeardown: false
        )
        weak var releasedBrowserManager = browserManager
        manager.attach(browserManager: try XCTUnwrap(browserManager))

        XCTAssertTrue(attachedRuntime.hasInstalledRuntime)
        browserManager = nil
        XCTAssertNil(releasedBrowserManager)

        inspection.browserPublication.reloads.finalizeRuntimeLoad(
            reason: #function,
            profileID: profile.id
        )

        let controller = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        var callbackCount = 0
        var completionError: (any Error)?
        inspection.normalTabs.requestedTabs.openWindow(
            tabURLs: [URL(string: "https://example.com")!],
            controller: controller,
            extensionContext: nil,
            completion: { _, error in
                callbackCount += 1
                completionError = error
            }
        )

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(
            (completionError as NSError?)?.code,
            ExtensionManagerCallbackError.browserManagerUnavailable.code
        )
    }

    func testExtensionRequestedInternalTabRendersThroughSumiWebViewPath() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Render Profile")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        _ = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedRenderedPage"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)

        let loadedContext = try await inspection.contextCoordination.residency.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controllersByProfile[profile.id]
        )
        publishNormalExtensionWindow(
            inspection: inspection,
            browserManager: browserManager,
            profile: profile
        )
        let evidence = try XCTUnwrap(
            inspection.controller.callbackAdmission.capture(
                context: extensionContext,
                controller: controller
            )
        )
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        let tab = try managerFixture.attachedRuntime.runtime.requestedTabs
            .opening.open(
            url: extensionURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            extensionContext: extensionContext,
            evidence: evidence,
            callbackAdmission: inspection.controller.callbackAdmission,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = try XCTUnwrap(
            tab.ensureUntrackedNormalWebView(
                reason: "SafariExtensionWebViewControllerWiringTests.extensionRender"
            )
        )

        let metrics = try await awaitExtensionRenderMetrics(in: webView)
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
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        _ = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        manager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerForTesting(), manager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionRequestedPage"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)

        let loadedContext = try await inspection.contextCoordination.residency.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controllersByProfile[profile.id]
        )
        publishNormalExtensionWindow(
            inspection: inspection,
            browserManager: browserManager,
            profile: profile
        )
        let evidence = try XCTUnwrap(
            inspection.controller.callbackAdmission.capture(
                context: extensionContext,
                controller: controller
            )
        )
        let extensionURL = extensionContext.baseURL
            .appendingPathComponent("popup.html")

        var didOpenCount = 0
        manager.testHooks.didOpenTab = { tabID in
            if browserManager.tabCollectionMembershipOwner.tab(for: tabID)?.url == extensionURL {
                didOpenCount += 1
            }
        }

        let tab = try managerFixture.attachedRuntime.runtime.requestedTabs
            .opening.open(
            url: extensionURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            extensionContext: extensionContext,
            evidence: evidence,
            callbackAdmission: inspection.controller.callbackAdmission,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(didOpenCount, 1)

        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: extensionURL)
        managerFixture.attachedRuntime.runtime.normalTabs.tabRegistration
            .markEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests.didCommit"
        )
        managerFixture.attachedRuntime.runtime.publications.tabActivation
            .activate(tab, previous: nil)

        XCTAssertEqual(
            didOpenCount,
            1,
            "Commit and activation callbacks must not duplicate the extension-created internal tab"
        )
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.currentOpenNotificationGeneration(),
            inspection.runtimeAuthorities.tabPublicationRevisions.issue()
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
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        _ = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "about:blank")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        registerWindowDisplaying(
            tab,
            profileId: profile.id,
            browserManager: browserManager
        )

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
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

        managerFixture.attachedRuntime.runtime.normalTabs.tabRegistration
            .markEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        wait(for: [didOpenExpectation], timeout: 2)
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.currentOpenNotificationGeneration(),
            inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        )
        XCTAssertTrue(tab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)
    }

    func testMarkTabEligibleAfterCommittedNavigationDoesNotNotifyTwice() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        _ = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "about:blank")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        registerWindowDisplaying(
            tab,
            profileId: profile.id,
            browserManager: browserManager
        )

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
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

        managerFixture.attachedRuntime.runtime.normalTabs.tabRegistration
            .markEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests.first"
        )
        managerFixture.attachedRuntime.runtime.normalTabs.tabRegistration
            .markEligibleAfterCommittedNavigation(
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
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        let expectedController = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let pageURL = server.loginBasicURL
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(
            profileId: profile.id,
            url: pageURL,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        registerWindowDisplaying(
            tab,
            profileId: profile.id,
            browserManager: browserManager
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            inspection: inspection,
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

        managerFixture.attachedRuntime.runtime.normalTabs.tabRegistration
            .markEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
        XCTAssertNotNil(
            attachedRuntime.runtime.controller.tabWebViewResolver.extensionWebView(
                for: tab,
                extensionContext: extensionContext
            )
        )
    }

    private final class RequestedWindowPreparedStub:
        PreparedExtensionRequestedWindow {
        let window = BrowserWindowState()
        private(set) var presentCallCount = 0
        private(set) var presentedActivationValues: [Bool] = []
        private(set) var acceptCallCount = 0
        private(set) var cancelCallCount = 0

        func present(activate: Bool) -> Bool {
            presentCallCount += 1
            presentedActivationValues.append(activate)
            return true
        }

        func accept() -> Bool {
            acceptCallCount += 1
            return true
        }

        func cancel() {
            cancelCallCount += 1
        }
    }

    private final class RequestedWindowCreatorStub:
        ExtensionRequestedWindowCreating {
        let prepared: RequestedWindowPreparedStub
        private(set) var preparedSeeds: [ExtensionRequestedWindowSeed] = []

        init(prepared: RequestedWindowPreparedStub) {
            self.prepared = prepared
        }

        func prepareExtensionRequestedWindow(
            _ seed: ExtensionRequestedWindowSeed
        ) -> (any PreparedExtensionRequestedWindow)? {
            preparedSeeds.append(seed)
            return prepared
        }
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
