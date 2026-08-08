import AppKit
import Combine
import CoreGraphics
import class SwiftUI.NSHostingView
import XCTest

@testable import Sumi

@MainActor
extension SidebarSpaceBodyInjectionRegressionTests {
    func testURLBarDisplayModelIgnoresActionPolicyAndCatalogMetadata() async throws {
        let suiteName = "SumiTests.ActionButtonProjection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.enable(.extensions)
        let container = try makeInMemoryStartupDatabase()
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
        var inspection: ExtensionManagerTestInspection?
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            managerFactory: { context, profile, configuration, registry in
                ExtensionManager(
            database: context,
                    initialProfile: profile,
                    browserConfiguration: configuration,
                    moduleRegistry: registry,
                    testInspectionDidAssemble: { inspection = $0 }
                )
            },
            surfaceStore: surfaceStore
        )
        let browserRuntime = attachBrowserRuntime(to: module)
        defer { withExtendedLifetime(browserRuntime) {} }
        _ = module.managerForTesting()
        let actionSurfaces = try XCTUnwrap(inspection).actionSurfaces
        await drainMainActorTurns()
        actionSurfaces.installedExtensions.upsert(
            makeToolbarExtension(version: "1.0", name: "Toolbar Action")
        )
        await drainMainActorTurns()
        let model = URLBarExtensionDisplayModel(
            moduleEnabledChanges: module.enabledChanges,
            current: { module.toolbarPresentationSnapshot(profileID: $0) },
            changes: { module.toolbarPresentationSnapshots(profileID: $0) }
        )
        model.setDemanded(true, profileID: nil)
        defer { model.setDemanded(false, profileID: nil) }
        var displayChanges = 0
        let changes = model.$snapshot.dropFirst().sink { _ in
            displayChanges += 1
        }

        actionSurfaces.publication.setActionSurfaceState(
            makeActionState(extensionID: "unrelated-extension", label: "Other"),
            extensionID: "unrelated-extension"
        )
        surfaceStore.refreshSiteAccessPolicies(profileId: UUID())
        await drainMainActorTurns()
        XCTAssertEqual(displayChanges, 0)

        actionSurfaces.installedExtensions.upsert(
            makeToolbarExtension(version: "2.0", name: "Toolbar Action")
        )
        await drainMainActorTurns()
        XCTAssertEqual(displayChanges, 0)
        XCTAssertEqual(model.snapshot.extensions.first?.name, "Toolbar Action")

        actionSurfaces.installedExtensions.upsert(
            makeToolbarExtension(version: "2.0", name: "Renamed Action")
        )
        await drainMainActorTurns()
        XCTAssertEqual(displayChanges, 1)
        XCTAssertEqual(
            model.snapshot.extensions.first?.name,
            "Renamed Action"
        )
        module.pinToToolbar("toolbar-extension", profileId: nil)
        await drainMainActorTurns()
        XCTAssertEqual(
            model.snapshot.pinnedExtensionIDs,
            ["toolbar-extension"]
        )
        module.unpinFromToolbar("toolbar-extension", profileId: nil)
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot.pinnedExtensionIDs, [])

        actionSurfaces.installedExtensions.upsert(
            makeToolbarExtension(
                version: "2.0",
                name: "Renamed Action",
                isEnabled: false
            )
        )
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot.enabledExtensions, [])
        actionSurfaces.installedExtensions.upsert(
            makeToolbarExtension(
                version: "2.0",
                name: "Renamed Action"
            )
        )
        await drainMainActorTurns()
        XCTAssertEqual(
            model.snapshot.enabledExtensions.map(\.id),
            ["toolbar-extension"]
        )
        withExtendedLifetime(changes) {}
    }

    func testExtensionDisplayDemandSubscribesOnlyWhileEnteredAndEnabled() async {
        let enabled = CurrentValueSubject<Bool, Never>(false)
        let presentationChanges = PassthroughSubject<
            BrowserExtensionToolbarPresentationSnapshot,
            Never
        >()
        var currentReads = 0
        var publisherCreations = 0
        var subscriptions = 0
        var cancellations = 0
        let model = URLBarExtensionDisplayModel(
            moduleEnabledChanges: enabled.eraseToAnyPublisher(),
            current: { _ in
                currentReads += 1
                return .empty
            },
            changes: { _ in
                publisherCreations += 1
                return presentationChanges
                    .handleEvents(
                        receiveSubscription: { _ in subscriptions += 1 },
                        receiveCancel: { cancellations += 1 }
                    )
                    .eraseToAnyPublisher()
            }
        )

        XCTAssertEqual(currentReads, 0)
        XCTAssertEqual(publisherCreations, 0)
        model.setDemanded(true, profileID: UUID())
        XCTAssertEqual(currentReads, 0)
        XCTAssertEqual(subscriptions, 0)

        enabled.send(true)
        XCTAssertEqual(currentReads, 1)
        XCTAssertEqual(publisherCreations, 1)
        XCTAssertEqual(subscriptions, 1)
        presentationChanges.send(
            BrowserExtensionToolbarPresentationSnapshot(
                display: .empty,
                pinnedExtensionIDs: ["mounted"],
                unpinnedExtensionIDs: []
            )
        )
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot.pinnedExtensionIDs, ["mounted"])

        model.setDemanded(false, profileID: nil)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(model.snapshot, .empty)
        enabled.send(false)
        enabled.send(true)
        XCTAssertEqual(publisherCreations, 1)
        XCTAssertEqual(currentReads, 1)
    }

    func testCrossProfileTransitionNeverUsesGlobalActionBadgeOrIcon()
        async throws {
        let suiteName = "SumiTests.TransitionActionProjection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.enable(.extensions)
        let container = try makeInMemoryStartupDatabase()
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
        var inspection: ExtensionManagerTestInspection?
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            managerFactory: { context, profile, configuration, registry in
                ExtensionManager(
            database: context,
                    initialProfile: profile,
                    browserConfiguration: configuration,
                    moduleRegistry: registry,
                    testInspectionDidAssemble: { inspection = $0 }
                )
            },
            surfaceStore: surfaceStore
        )
        let browserRuntime = attachBrowserRuntime(to: module)
        defer { withExtendedLifetime(browserRuntime) {} }
        _ = module.managerForTesting()
        let actionSurfaces = try XCTUnwrap(inspection).actionSurfaces
        let sourceProfileID = UUID()
        let destinationProfileID = UUID()
        let records = (0..<3).map {
            BrowserExtensionToolbarDisplayRecord(
                makeToolbarExtension(
                    id: "transition-\($0)",
                    version: "1.0",
                    name: "Transition \($0)"
                )
            )
        }
        let ids = records.map(\.id)
        actionSurfaces.toolbarPinning.replacePinnedToolbarExtensionIDsByProfile([
            ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(
                for: sourceProfileID
            ): ids,
            ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(
                for: destinationProfileID
            ): ids,
        ])
        let globalIcon = NSImage(size: NSSize(width: 9, height: 9))
        for id in ids {
            actionSurfaces.publication.setActionSurfaceState(
                BrowserExtensionActionSurfaceState(
                    extensionID: id,
                    label: "Wrong Profile",
                    badgeText: "WRONG",
                    hasUnreadBadgeText: true,
                    isEnabled: true,
                    presentsPopup: false,
                    icon: globalIcon
                ),
                extensionID: id
            )
        }
        await drainMainActorTurns()
        let staticIcon = NSImage(size: NSSize(width: 3, height: 3))
        surfaceStore.iconCache.imageLoader = { _ in staticIcon }
        let sourceSlots = module.orderedPinnedToolbarSlots(
            enabledExtensions: records,
            profileId: sourceProfileID
        )
        let destinationSlots = module.orderedPinnedToolbarSlots(
            enabledExtensions: records,
            profileId: destinationProfileID
        )

        let source = SpaceSidebarTransitionSnapshotBuilder
            .transitionExtensionActionsSnapshot(
                slots: sourceSlots,
                surfaceStore: surfaceStore
            )
        let destination = SpaceSidebarTransitionSnapshotBuilder
            .transitionExtensionActionsSnapshot(
                slots: destinationSlots,
                surfaceStore: surfaceStore
            )

        XCTAssertEqual(source.slots.count, 3)
        XCTAssertEqual(destination.slots.count, 3)
        for slot in source.slots + destination.slots {
            XCTAssertNil(slot.badgeText)
            XCTAssertFalse(slot.hasUnreadBadgeText)
            XCTAssertTrue(slot.icon === staticIcon)
            XCTAssertFalse(slot.icon === globalIcon)
        }
    }

    func testActionButtonModelScopesEveryFieldToExactProfileAndPage() async {
        let extensionID = "target-extension"
        let profileA = UUID()
        let profileB = UUID()
        let windowID = UUID()
        let window = BrowserWindowState(id: windowID)
        let registry = WindowRegistry()
        XCTAssertEqual(registry.register(window), .registered)
        defer { registry.unregister(windowID) }
        let tabA = Tab(
            url: URL(string: "https://a.example")!,
            loadsCachedFaviconOnInit: false
        )
        let tabB = Tab(
            url: URL(string: "https://b.example")!,
            loadsCachedFaviconOnInit: false
        )
        tabA.profileId = profileA
        tabB.profileId = profileB
        let contextA = NSObject()
        let contextB = NSObject()
        let adapterA = NSObject()
        let adapterB = NSObject()
        let targetA = makeActionTarget(
            extensionID: extensionID,
            profileID: profileA,
            window: window,
            registry: registry,
            tab: tabA,
            context: contextA,
            adapter: adapterA
        )
        let targetB = makeActionTarget(
            extensionID: extensionID,
            profileID: profileB,
            window: window,
            registry: registry,
            tab: tabB,
            context: contextB,
            adapter: adapterB
        )
        let iconA = NSImage(size: NSSize(width: 1, height: 1))
        let iconB = NSImage(size: NSSize(width: 2, height: 2))
        let snapshotState = ExtensionActionSnapshotQueryOracle([
            targetA: BrowserExtensionActionButtonSnapshot(
                label: "Profile A",
                badgeText: "A",
                hasUnreadBadgeText: false,
                isEnabled: true,
                icon: iconA
            ),
            targetB: BrowserExtensionActionButtonSnapshot(
                label: "Profile B",
                badgeText: "B",
                hasUnreadBadgeText: true,
                isEnabled: false,
                icon: iconB
            ),
        ])
        let changes = PassthroughSubject<
            ExtensionActionPresentationChange,
            Never
        >()
        let model = BrowserExtensionActionButtonModel(
            changes: changes.eraseToAnyPublisher(),
            query: { snapshotState.snapshots[$0] }
        )
        var publications = 0
        let cancellable = model.$snapshot.dropFirst().sink { _ in
            publications += 1
        }

        model.setTarget(targetA)
        XCTAssertEqual(model.snapshot.label, "Profile A")
        XCTAssertEqual(model.snapshot(for: targetA).label, "Profile A")
        XCTAssertEqual(model.snapshot(for: targetB), .unavailable)
        XCTAssertEqual(model.snapshot(for: nil), .unavailable)
        XCTAssertNil(
            BrowserExtensionActionButtonSnapshot.unavailable.isEnabled,
            "An unresolved action must stay clickable so its first click can lazily load the WebKit context"
        )
        let afterInitialTarget = publications

        changes.send(
            .init(extensionID: "other-extension", profileID: profileA)
        )
        changes.send(.init(extensionID: extensionID, profileID: profileB))
        await drainMainActorTurns()
        XCTAssertEqual(publications, afterInitialTarget)
        XCTAssertEqual(model.snapshot.label, "Profile A")

        changes.send(.init(extensionID: extensionID, profileID: profileA))
        model.setTarget(targetB)
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot.label, "Profile B")
        XCTAssertEqual(model.snapshot.badgeText, "B")
        XCTAssertTrue(model.snapshot.hasUnreadBadgeText)
        XCTAssertEqual(model.snapshot.isEnabled, false)
        XCTAssertTrue(model.snapshot.icon === iconB)

        snapshotState.snapshots[targetA] = BrowserExtensionActionButtonSnapshot(
            label: "Stale Profile A",
            badgeText: "STALE",
            hasUnreadBadgeText: false,
            isEnabled: true,
            icon: iconA
        )
        changes.send(.init(extensionID: extensionID, profileID: profileA))
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot.label, "Profile B")
        XCTAssertEqual(model.snapshot.badgeText, "B")
        XCTAssertTrue(model.snapshot.icon === iconB)
        withExtendedLifetime((cancellable, contextA, contextB, adapterA, adapterB)) {}
    }

    func testProfileTransitionPublishesOnlyThroughExactAuthority() {
        let browserManager = BrowserManager()
        var browserManagerChanges = 0
        var transitionValues: [Bool] = []
        let broad = browserManager.objectWillChange.sink {
            browserManagerChanges += 1
        }
        let exact = browserManager.currentProfileAuthority.$isTransitioning.sink {
            transitionValues.append($0)
        }

        browserManager.isTransitioningProfile = true
        browserManager.isTransitioningProfile = false

        XCTAssertEqual(browserManagerChanges, 0)
        XCTAssertEqual(transitionValues, [false, true, false])
        withExtendedLifetime((broad, exact)) {}
    }

    func testSidebarColumnHostedRootCarriesInjectedDragState() throws {
        let nowPlayingController = SumiNativeNowPlayingController()
        let updaterService = SumiUpdaterService(backendFactory: { _ in nil })
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            nowPlayingController: nowPlayingController
        )
        let windowState = BrowserWindowState()
        windowRegistry.register(windowState)
        let viewContext = WindowSidebarContext.make(
            browserManager: browserManager,
            updaterService: updaterService,
            nowPlayingController: SumiNativeNowPlayingController()
        )
        let dragState = SidebarDragState()
        let settingsSuiteName = "SumiTests.sidebarDragState.\(UUID().uuidString)"
        let settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuiteName))
        defer {
            settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
        }

        let environmentContext = SidebarHostEnvironmentContext(
            browserContext: viewContext.browserContext,
            hostActions: SidebarHostActions(
                updateSidebarWidth: { _, _, _ in /* No-op. */ },
                persistWindowSession: { _ in /* No-op. */ },
                dismissThemePickerCommittingIfNeeded: { /* No-op. */ }
            ),
            windowState: windowState,
            windowRegistry: windowRegistry,
            sumiSettings: SumiSettingsService(userDefaults: settingsDefaults),
            keyboardShortcutManager: KeyboardShortcutManager(),
            nowPlayingController: nowPlayingController,
            updaterService: updaterService,
            resolvedThemeContext: .default,
            chromeBackgroundResolvedThemeContext: .default,
            windowChromeSize: CGSize(width: 320, height: 640),
            sidebarDragState: dragState
        )
        let presentationContext: SidebarPresentationContext = .docked(
            sidebarWidth: 280
        )
        let root = SidebarColumnHostedRoot.view(
            environmentContext: environmentContext,
            presentationContext: presentationContext,
            spaceCatalog: viewContext.spaceCatalog,
            inventory: viewContext.inventory,
            selection: viewContext.selection,
            pinProjection: viewContext.pinProjection,
            pinCommands: viewContext.pinCommands,
            pinExecution: viewContext.pinExecution,
            folderCommands: viewContext.folderCommands,
            spaceLifecycle: viewContext.spaceLifecycle,
            regularTabCatalog: viewContext.regularTabCatalog,
            regularTabTargets: viewContext.regularTabTargets,
            regularTabLifecycleCommands:
                viewContext.regularTabLifecycleCommands,
            regularTabShortcutCommands:
                viewContext.regularTabShortcutCommands,
            regularTabPlacementCommands:
                viewContext.regularTabPlacementCommands,
            dragTransactions: viewContext.dragTransactions,
            inventoryUpdates: viewContext.inventoryUpdates,
            profileUpdates: viewContext.profileUpdates
        )

        XCTAssertIdentical(root.environmentContext.sidebarDragState, dragState)
        XCTAssertIdentical(root.environmentContext.sidebarDragState.locationTracker, dragState.locationTracker)
        XCTAssertIdentical(root.environmentContext.nowPlayingController, nowPlayingController)
        XCTAssertIdentical(root.environmentContext.updaterService, updaterService)
        XCTAssertIdentical(
            root.environmentContext.browserContext.extensionSurfaceStore,
            browserManager.optionalModules.extensions.surfaceStore
        )
        XCTAssertEqual(root.presentationContext, presentationContext)
    }

}
