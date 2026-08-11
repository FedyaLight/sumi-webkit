import AppKit
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionWebViewControllerRuntimeWarmupTests: SafariExtensionWebViewControllerWiringTestCase {
    func testNotifyTabOpenedDefersUntilContentScriptContextsLoad() async throws {
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

        let browserManager = makeBrowserManager(
            profile: profile
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        inspection.contextCoordination.residency.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "http://127.0.0.1:8765/login-basic.html")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        registerWindowDisplaying(
            tab,
            profileId: profile.id,
            browserManager: browserManager
        )
        tab.extensionPageRuntimeOwner.markEligible(for: inspection.runtimeAuthorities.tabPublicationRevisions.issue())

        XCTAssertFalse(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )
        XCTAssertFalse(
            managerFixture.attachedRuntime.runtime.normalTabs.tabOpening
                .publishOpen(tab)
        )
        let deferredTask = attachedRuntime.runtime.normalTabs
            .deferredTabRegistration.task(for: tab.id)

        await inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .ensureContentScriptContextsLoaded(for: profile.id)
        await deferredTask?.value
        attachUsableExtensionWebView(
            to: tab,
            inspection: inspection,
            profile: profile
        )
        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )
        XCTAssertTrue(
            managerFixture.attachedRuntime.runtime.normalTabs.tabOpening
                .publishOpen(tab)
        )
        XCTAssertEqual(tab.extensionPageRuntimeOwner.openNotifiedContextReadiness, .loaded)
    }

    func testNotifyTabOpenedPublishesBeforeNativeMessagingWarmup() async throws {
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

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        let entity = try XCTUnwrap(try inspection.installation.metadata.extensionMetadata(for: installed.id))
        entity.isEnabled = true
        try inspection.installation.metadata.save(entity)
        _ = inspection.installation.catalog.load()

        await inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .ensureContentScriptContextsLoaded(for: profile.id)

        var backgroundWakeCount = 0
        var backgroundWakeKey: String?
        var backgroundWakeObservations: [String] = []
        manager.testHooks.backgroundContentWake = { wakeKey, extensionContext in
            backgroundWakeKey = wakeKey
            let contextIdentity = inspection.contextState.profiles.contextIdentity(for: extensionContext)
            let stateBefore = self.backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            )
            backgroundWakeObservations.append(
                "wake=\(backgroundWakeCount + 1) key=\(wakeKey) expectedProfile=\(profile.id) contextProfile=\(contextIdentity?.profileId.uuidString ?? "nil") stateBefore=\(stateBefore)"
            )
            backgroundWakeCount += 1
        }
        defer {
            manager.testHooks.backgroundContentWake = nil
        }

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://example.com/login")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        registerWindowDisplaying(
            tab,
            profileId: profile.id,
            browserManager: browserManager
        )
        tab.extensionPageRuntimeOwner.markEligible(for: inspection.runtimeAuthorities.tabPublicationRevisions.issue())
        attachUsableExtensionWebView(
            to: tab,
            inspection: inspection,
            profile: profile
        )

        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )
        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileNeedsInitialDocumentNativeMessagingWarmup(
                    profileId: profile.id
                )
        )
        XCTAssertTrue(
            managerFixture.attachedRuntime.runtime.normalTabs.tabOpening
                .publishOpen(tab)
        )
        XCTAssertTrue(tab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)
        XCTAssertNil(
            attachedRuntime.runtime.normalTabs.deferredTabRegistration.task(
                for: tab.id
            )
        )
        XCTAssertEqual(backgroundWakeCount, 0, backgroundWakeObservations.joined(separator: "\n"))
        XCTAssertNil(backgroundWakeKey)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .neverLoaded
        )
    }

    func testNotifyTabOpenedDefersUntilLiveWebViewExists() async throws {
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

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        await inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .ensureContentScriptContextsLoaded(for: profile.id)

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://example.com/login")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        registerWindowDisplaying(
            tab,
            profileId: profile.id,
            browserManager: browserManager
        )
        tab.extensionPageRuntimeOwner.markEligible(for: inspection.runtimeAuthorities.tabPublicationRevisions.issue())

        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )
        XCTAssertFalse(
            managerFixture.attachedRuntime.runtime.normalTabs.tabOpening
                .publishOpen(tab)
        )
        XCTAssertFalse(tab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)

        attachUsableExtensionWebView(
            to: tab,
            inspection: inspection,
            profile: profile
        )

        XCTAssertTrue(
            managerFixture.attachedRuntime.runtime.normalTabs.tabOpening
                .publishOpen(tab)
        )
        XCTAssertEqual(tab.extensionPageRuntimeOwner.openNotifiedContextReadiness, .loaded)
    }

    func testUserGestureReconcileDoesNotRebuildLivePageForMissedContentScriptBinding()
        async throws {
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

        let windowRegistry = WindowRegistry()
        let browserManager = makeBrowserManager(
            profile: profile,
            windowRegistry: windowRegistry
        )
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
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
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        await inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .ensureContentScriptContextsLoaded(for: profile.id)

        let pageURL = URL(string: "https://example.com/login")!
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: pageURL.absoluteString,
            in: space,
            activate: false
        )
        tab.profileId = profile.id
        tab.extensionPageRuntimeOwner.markEligible(for: inspection.runtimeAuthorities.tabPublicationRevisions.issue())
        let webView = attachUsableExtensionWebView(
            to: tab,
            inspection: inspection,
            profile: profile
        )
        browserManager.testWebViewRuntime().trackedWebViewAdmission.attemptAssignment(
            webView,
            to: tab,
            in: windowState.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertTrue(
            managerFixture.attachedRuntime.runtime.normalTabs.tabRebind
                .needsContentScriptRebind(tab)
        )
        let webViewBeforeGesture = try XCTUnwrap(tab.resolvedCurrentWebView())

        managerFixture.attachedRuntime.runtime.normalTabs.tabRebind
            .reconcileOnUserGestureIfNeeded(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(tab.resolvedCurrentWebView(), webViewBeforeGesture)
    }

    func testExtensionRequestedNormalTabPreloadsContentScriptContextsBeforeOpenNotification() async throws {
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
        let controller = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)
        let bootstrapTab = makeTab(
            profileId: profile.id,
            url: URL(string: "about:blank")!,
            browserManager: browserManager
        )
        bootstrapTab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        registerWindowDisplaying(
            bootstrapTab,
            profileId: profile.id,
            browserManager: browserManager
        )
        attachUsableExtensionWebView(
            to: bootstrapTab,
            inspection: inspection,
            profile: profile
        )
        bootstrapTab.extensionPageRuntimeOwner.markEligible(
            for: inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        )
        XCTAssertTrue(
            managerFixture.attachedRuntime.runtime.normalTabs.tabOpening
                .publishOpen(bootstrapTab)
        )
        let targetSpaceID = try XCTUnwrap(bootstrapTab.spaceId)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        inspection.contextCoordination.residency.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )

        let pageURL = URL(string: "https://example.com/login")!
        XCTAssertFalse(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )

        let preparedProfileId = try await managerFixture.attachedRuntime.runtime
            .requestedTabs.contextPreloader.prepare(
            url: pageURL,
            requestedWindow: nil,
            controller: controller
        )

        XCTAssertEqual(preparedProfileId, profile.id)
        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )

        var openedTabIDs: [UUID] = []
        var deferredOpenReasons: [String] = []
        manager.testHooks.didOpenTab = { openedTabIDs.append($0) }
        manager.testHooks.didDeferOpenTab = { _, reason in
            deferredOpenReasons.append(reason)
        }
        defer { manager.clearDebugState() }

        let tab = try managerFixture.attachedRuntime.runtime.requestedTabs
            .opening.open(
            url: pageURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(tab.url, pageURL)
        XCTAssertEqual(tab.spaceId, targetSpaceID)
        XCTAssertNil(tab.webViewConfigurationOverride)
        XCTAssertNotNil(tab.resolvedAssignedWebView() ?? tab.resolvedCurrentWebView())
        XCTAssertEqual(
            openedTabIDs.filter { $0 == tab.id }.count,
            1,
            "deferredOpenReasons=\(deferredOpenReasons)"
        )
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.openNotifiedContextReadiness,
            .loaded,
            "deferredOpenReasons=\(deferredOpenReasons)"
        )
        XCTAssertTrue(tab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)
    }

    func testExtensionRequestedNormalTabDoesNotWakeNativeMessagingBackgrounds() async throws {
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
        let controller = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)
        let bootstrapTab = makeTab(
            profileId: profile.id,
            url: URL(string: "about:blank")!,
            browserManager: browserManager
        )
        bootstrapTab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        registerWindowDisplaying(
            bootstrapTab,
            profileId: profile.id,
            browserManager: browserManager
        )
        attachUsableExtensionWebView(
            to: bootstrapTab,
            inspection: inspection,
            profile: profile
        )
        bootstrapTab.extensionPageRuntimeOwner.markEligible(
            for: inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        )
        XCTAssertTrue(
            managerFixture.attachedRuntime.runtime.normalTabs.tabOpening
                .publishOpen(bootstrapTab)
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        let entity = try XCTUnwrap(try inspection.installation.metadata.extensionMetadata(for: installed.id))
        entity.isEnabled = true
        try inspection.installation.metadata.save(entity)
        _ = inspection.installation.catalog.load()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }
        defer {
            manager.testHooks.backgroundContentWake = nil
        }

        let pageURL = URL(string: "https://example.com/login")!
        XCTAssertFalse(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )

        let preparedProfileId = try await managerFixture.attachedRuntime.runtime
            .requestedTabs.contextPreloader.prepare(
            url: pageURL,
            requestedWindow: nil,
            controller: controller
        )

        XCTAssertEqual(preparedProfileId, profile.id)
        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )
        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileNeedsInitialDocumentNativeMessagingWarmup(
                    profileId: profile.id
                )
        )
        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .neverLoaded
        )

        _ = try managerFixture.attachedRuntime.runtime.requestedTabs.opening
            .open(
            url: pageURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .neverLoaded
        )
    }

    func testExtensionRequestedNormalWindowPreloadsContentScriptContextsBeforeOpenNotification() async throws {
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
        let controller = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
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
        _ = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        inspection.contextCoordination.residency.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )

        let pageURL = URL(string: "https://example.com/login")!
        XCTAssertFalse(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )

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

        attachedRuntime.runtime.requestedTabs.windowRouter.open(
            tabURLs: [pageURL],
            controller: controller,
            extensionContext: nil,
            completion: { window, error in
                completionWindow = window
                completionError = error
                openedWindow.fulfill()
            }
        )

        await fulfillment(of: [openedWindow], timeout: 2.0)
        XCTAssertNil(completionError)
        XCTAssertNotNil(completionWindow)
        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )

        let tab = try XCTUnwrap(
            browserManager.tabCollectionMembershipOwner.allTabs().first { $0.url == pageURL }
        )
        XCTAssertNotNil(tab.resolvedAssignedWebView() ?? tab.resolvedCurrentWebView())
        XCTAssertEqual(
            openedTabIDs.count,
            1,
            "deferredOpenReasons=\(deferredOpenReasons)"
        )
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.openNotifiedContextReadiness,
            .loaded,
            "deferredOpenReasons=\(deferredOpenReasons)"
        )
        XCTAssertTrue(tab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)
    }

    func testLazyContentScriptContextLoadDoesNotWakeBackgroundForOrdinaryNavigation() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptBackgroundProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )

        let entity = try XCTUnwrap(try inspection.installation.metadata.extensionMetadata(for: installed.id))
        entity.isEnabled = true
        try inspection.installation.metadata.save(entity)
        _ = inspection.installation.catalog.load()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }

        await inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .ensureContentScriptContextsLoaded(for: profile.id)

        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )
        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .neverLoaded
        )

        inspection.actionSurfaces.publication.markRuntimePublicationReady()
        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
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
        tab.extensionPageRuntimeOwner.markEligible(for: inspection.runtimeAuthorities.tabPublicationRevisions.issue())
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 0
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

        managerFixture.attachedRuntime.runtime.normalTabs.tabRebind
            .prepareBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: pageURL,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .neverLoaded
        )
    }

    func testDeferredTabNotificationDoesNotWarmNativeMessagingAfterContextLoad() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )

        let entity = try XCTUnwrap(try inspection.installation.metadata.extensionMetadata(for: installed.id))
        entity.isEnabled = true
        try inspection.installation.metadata.save(entity)
        _ = inspection.installation.catalog.load()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }

        await inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .ensureContentScriptContextsLoaded(for: profile.id)

        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )
        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .neverLoaded
        )
        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileNeedsInitialDocumentNativeMessagingWarmup(
                    profileId: profile.id
                )
        )
        XCTAssertFalse(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileNeedsInitialDocumentExtensionContextLoad(
                    profileId: profile.id
                )
        )

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
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
        defer {
            manager.testHooks.backgroundContentWake = nil
        }

        attachedRuntime.runtime.normalTabs.deferredTabRegistration
            .scheduleDeferredTabNotificationAfterContextLoad(
            tab,
            profileId: profile.id,
            extensionLoadRevision:
                inspection.runtimeAuthorities.loadRevisions.issue(),
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let deferredTask = attachedRuntime.runtime.normalTabs
            .deferredTabRegistration.task(for: tab.id)

        await deferredTask?.value

        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .neverLoaded
        )
        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileNeedsInitialDocumentNativeMessagingWarmup(
                    profileId: profile.id
                )
        )
    }

    func testInitialDocumentWarmupDoesNotWakeBackgroundWithoutNativeMessaging() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptBackgroundProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )

        let entity = try XCTUnwrap(try inspection.installation.metadata.extensionMetadata(for: installed.id))
        entity.isEnabled = true
        try inspection.installation.metadata.save(entity)
        _ = inspection.installation.catalog.load()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }

        await inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .ensureInitialExtensionContextsLoaded(for: profile.id)

        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )
        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .neverLoaded
        )
    }

    func testInitialContextPreparationDoesNotWarmNativeMessaging() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptNativeMessagingProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )

        let entity = try XCTUnwrap(try inspection.installation.metadata.extensionMetadata(for: installed.id))
        entity.isEnabled = true
        try inspection.installation.metadata.save(entity)
        _ = inspection.installation.catalog.load()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }

        await inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .ensureInitialExtensionContextsLoaded(for: profile.id)

        XCTAssertEqual(backgroundWakeCount, 0)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .neverLoaded
        )

        await inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .warmInitialDocumentNativeMessaging(for: profile.id)

        XCTAssertEqual(backgroundWakeCount, 1)

        let context = try XCTUnwrap(
            inspection.contextState.profiles.contexts(for: profile.id)[installed.id]
        )
        let nativeMessagingPermission = WKWebExtension.Permission(rawValue: "nativeMessaging")
        XCTAssertTrue(context.isLoaded)
        XCTAssertTrue(
            ExtensionPermissionStatusResolver.isGranted(
                context.permissionStatus(for: nativeMessagingPermission)
            )
        )
        XCTAssertTrue(
            inspection.normalTabs.deferredRuntime
                .initialDocumentRuntimePreparationOwner
                .profileHasLoadedContentScriptContexts(profileId: profile.id)
        )
        XCTAssertEqual(backgroundWakeCount, 1)
        XCTAssertEqual(
            backgroundRuntimeState(
                in: inspection,
                extensionID: installed.id,
                profileID: profile.id
            ),
            .loaded
        )
        XCTAssertEqual(
            inspection.runtimeAuthorities.metrics.metrics(
                for:
                ExtensionRuntimeResidencyState.scopedKey(
                    extensionId: installed.id,
                    profileId: profile.id
                )
            )?.lastBackgroundWakeReason,
            .nativeMessaging
        )
    }

}
