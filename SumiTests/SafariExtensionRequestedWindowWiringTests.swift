import AppKit
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)

@MainActor
extension SafariExtensionWebViewControllerWiringTests {
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
