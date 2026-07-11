import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionWebViewControllerRuntimeWarmupTests: SafariExtensionWebViewControllerWiringTestCase {
    func testTabNeedsExtensionContentScriptRebindWhenContextsWereNotLoadedAtNotify() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextReadiness = .missing
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

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

        let browserManager = makeBrowserManager(
            profile: profile
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        manager.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "http://127.0.0.1:8765/login-basic.html")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.runtimeSession.tabOpenNotificationGeneration

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
        XCTAssertEqual(tab.extensionPageRuntimeOwner.openNotifiedContextReadiness, .loaded)
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
        _ = manager.installedExtensionCatalog.load()

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
            url: URL(string: "https://example.com/login")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.runtimeSession.tabOpenNotificationGeneration
        attachUsableExtensionWebView(
            to: tab,
            manager: manager,
            profile: profile
        )

        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertTrue(manager.profileNeedsInitialDocumentNativeMessagingWarmup(profileId: profile.id))
        XCTAssertFalse(manager.notifyTabOpened(tab))
        XCTAssertFalse(tab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)

        await fulfillment(of: [backgroundWakeExpectation], timeout: 3.0)
        if let deferredTask = manager.deferredTabNotificationTask(for: tab.id) {
            await deferredTask.value
        }
        XCTAssertEqual(backgroundWakeCount, 1, backgroundWakeObservations.joined(separator: "\n"))
        XCTAssertEqual(
            backgroundWakeKey,
            ExtensionRuntimeResidencyState.scopedKey(
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        await manager.ensureContentScriptContextsLoaded(for: profile.id)

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://example.com/login")!,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.runtimeSession.tabOpenNotificationGeneration

        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertFalse(manager.notifyTabOpened(tab))
        XCTAssertFalse(tab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)

        attachUsableExtensionWebView(
            to: tab,
            manager: manager,
            profile: profile
        )

        XCTAssertTrue(manager.notifyTabOpened(tab))
        XCTAssertEqual(tab.extensionPageRuntimeOwner.openNotifiedContextReadiness, .loaded)
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
        browserManager.bindTestWebViewCoordinator()
        let space = browserManager.tabManager.spaceServices.catalog.createSpace(
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        await manager.ensureContentScriptContextsLoaded(for: profile.id)

        let pageURL = URL(string: "https://example.com/login")!
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: pageURL.absoluteString,
            in: space,
            activate: false
        )
        tab.profileId = profile.id
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.runtimeSession.tabOpenNotificationGeneration
        let webView = attachUsableExtensionWebView(
            to: tab,
            manager: manager,
            profile: profile
        )
        browserManager.webViewOwnershipService?.assign(
            webView,
            to: tab,
            in: windowState.id
        )
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
        let webViewBeforeGesture = try XCTUnwrap(tab.resolvedCurrentWebView())

        manager.reconcileExtensionRuntimeOnUserGestureIfNeeded(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(tab.resolvedCurrentWebView(), webViewBeforeGesture)
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

        let browserManager = makeBrowserManager(
            profile: profile
        )
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        browserManager.bindTestWebViewCoordinator()
        let space = browserManager.tabManager.spaceServices.catalog.createSpace(
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        manager.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )

        let pageURL = URL(string: "https://example.com/login")!
        XCTAssertFalse(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))

        let preparedProfileId = try await manager.requestedTabContextPreloader.prepare(
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

        let tab = try manager.requestedTabOpening.open(
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

        let browserManager = makeBrowserManager(
            profile: profile
        )
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        browserManager.bindTestWebViewCoordinator()
        let space = browserManager.tabManager.spaceServices.catalog.createSpace(
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
        _ = manager.installedExtensionCatalog.load()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }
        defer {
            manager.testHooks.backgroundContentWake = nil
        }

        let pageURL = URL(string: "https://example.com/login")!
        XCTAssertFalse(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))

        let preparedProfileId = try await manager.requestedTabContextPreloader.prepare(
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

        _ = try manager.requestedTabOpening.open(
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
        browserManager.bindTestWebViewCoordinator()
        let space = browserManager.tabManager.spaceServices.catalog.createSpace(
            name: "Work",
            profileId: profile.id
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
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
            browserManager.tabManager.tabCollectionMembershipOwner.allTabs().first { $0.url == pageURL }
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
        _ = manager.installedExtensionCatalog.load()

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
        manager.runtimeSession.tabOpenNotificationGeneration = 17
        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.runtimeSession.tabOpenNotificationGeneration
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 0
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

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
        _ = manager.installedExtensionCatalog.load()

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
        _ = manager.installedExtensionCatalog.load()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }

        await manager.ensureInitialExtensionContextsLoaded(for: profile.id)

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
        _ = manager.installedExtensionCatalog.load()

        var backgroundWakeCount = 0
        manager.testHooks.backgroundContentWake = { _, _ in
            backgroundWakeCount += 1
        }

        await manager.ensureInitialExtensionContextsLoaded(for: profile.id)

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
            manager.runtimeSession.runtimeMetricsByExtensionID[
                ExtensionRuntimeResidencyState.scopedKey(
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
            _ = try await manager.extensionRuntimeLoader.loadEnabled(from: entity)
            XCTFail("A load invalidated by runtime teardown must not reach WebKit")
        } catch {
            XCTAssertTrue(error is CancellationError, String(describing: error))
        }

        XCTAssertTrue(controller.extensionContexts.isEmpty)
        XCTAssertTrue(manager.profileRuntime.contextsByProfile.isEmpty)
        XCTAssertTrue(manager.profileRuntime.controllersByProfile.isEmpty)
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
        XCTAssertTrue(manager.profileRuntime.contextsByProfile.isEmpty)
        XCTAssertTrue(manager.profileRuntime.controllersByProfile.isEmpty)
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
        let browserManager = makeBrowserManager(
            profile: profile
        )
        manager.attach(browserManager: browserManager)
        let space = browserManager.tabManager.spaceServices.catalog.createSpace(
            name: "Work",
            profileId: profile.id
        )
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        _ = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        manager.extensionsLoaded = true

        let tabWithController = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/with-controller",
            in: space,
            activate: false
        )
        tabWithController.profileId = profile.id
        let controllerConfiguration = browserConfiguration
            .auxiliaryWebViewConfiguration(surface: .extensionOptions)
        manager.prepareWebViewConfigForExtensionRuntime(
            controllerConfiguration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webViewWithController = FocusableWKWebView(
            frame: .zero,
            configuration: controllerConfiguration
        )
        webViewWithController.owningTab = tabWithController
        tabWithController.replaceUntrackedWebView(webViewWithController)

        let tabWithoutController = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
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
        tabWithoutController.replaceUntrackedWebView(webViewWithoutController)

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
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 1
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 1
        tab.extensionPageRuntimeOwner.openNotifiedContextReadiness = .loaded

        XCTAssertNotNil(webView.configuration.webExtensionController)
        XCTAssertNotNil(tab.webViewConfigurationOverride)

        manager.rebuildLiveWebViewsAfterUserExtensionRuntimeTeardown(
            [tab],
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertNil(tab.webViewConfigurationOverride)
        XCTAssertNil(tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence)
        XCTAssertNil(tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration)
        XCTAssertEqual(tab.extensionPageRuntimeOwner.openNotifiedContextReadiness, .notNotified)
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
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: tab.url)
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = tab.extensionPageRuntimeOwner.documentSequence

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
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 0
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: tab.url)

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
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 0
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))

        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

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
        manager.runtimeSession.tabOpenNotificationGeneration = 21

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(
            profileId: profile.id,
            url: pageURL,
            browserManager: browserManager
        )
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

        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 0
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)
        tab.extensionPageRuntimeOwner.lastOpenNotificationGeneration = manager.runtimeSession.tabOpenNotificationGeneration
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.runtimeSession.tabOpenNotificationGeneration

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
        XCTAssertEqual(tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence, tab.extensionPageRuntimeOwner.documentSequence)
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration,
            manager.extensionContextBindingGeneration(for: profile.id)
        )

        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)
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
        let tab = makeTab(
            profileId: profile.id,
            url: pageURL,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 0
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.runtimeSession.tabOpenNotificationGeneration
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
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 0
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))

        manager.bumpExtensionContextBindingGeneration(
            for: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testWrongControllerRequiresRuntimeRebuild() throws {
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
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 0
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profileB.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        XCTAssertEqual(manager.resolvedProfileId(for: tab), profileA.id)
        XCTAssertIdentical(configuration.webExtensionController, controllerB)
        XCTAssertNotIdentical(configuration.webExtensionController, controllerA)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)
        let currentController = try XCTUnwrap(webView.configuration.webExtensionController)
        XCTAssertIdentical(currentController, controllerB)
        XCTAssertEqual(manager.profileId(for: currentController), profileB.id)
        XCTAssertEqual(manager.resolvedProfileId(for: tab), profileA.id)
        XCTAssertIdentical(manager.profileRuntime.controllersByProfile[profileA.id], controllerA)
        XCTAssertIdentical(manager.profileRuntime.controllersByProfile[profileB.id], controllerB)
        XCTAssertIdentical(manager.extensionController(for: tab), controllerA)

        XCTAssertTrue(
            manager.webViewNeedsExtensionRuntimeRebuild(
                currentController: currentController,
                currentURL: pageURL,
                for: tab
            )
        )
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
        let profile = Profile(name: "Profile A")
        let otherProfile = Profile(name: "Profile B")
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
        ExtensionRuntimeContextLoader.configureContextIdentity(
            extensionContext,
            extensionId: extensionId,
            profileId: profile.id
        )
        ExtensionRuntimeContextLoader.configureContextIdentity(
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
        manager.prepareWebViewConfigForExtensionRuntime(
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

}
