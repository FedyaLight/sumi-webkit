import AppKit
import Combine
import CoreGraphics
import XCTest

@testable import Sumi

@MainActor
final class SidebarSpaceBodyInjectionRegressionTests: XCTestCase {
    func testSidebarObservationSourcesSeparateInventoryFromProfileRuntime() {
        let browserManager = BrowserManager()
        let context = WindowSidebarContext.make(
            browserManager: browserManager,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil })
        )
        let targetSpaceID = UUID()
        let unrelatedSpaceID = UUID()
        let targetWindowID = UUID()
        var invalidationCount = 0
        let inventoryCancellable = context.inventoryUpdates.pageChanges(
            windowID: targetWindowID,
            spaceID: targetSpaceID,
            profileID: nil
        ).sink { _ in
            invalidationCount += 1
        }
        let profileCancellable = context.profileUpdates.runtime.sink { _ in
            invalidationCount += 1
        }
        let initialInvalidationCount = invalidationCount

        browserManager.isTransitioningProfile = true
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 1)

        browserManager.isTransitioningProfile = false
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 2)

        browserManager.currentProfile = Profile(name: "Sidebar Runtime")
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 3)

        browserManager.tabManager.tabStructureEventBus.publishStructureChanged(
            scope: .space(unrelatedSpaceID)
        )
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 3)

        browserManager.tabManager.tabStructureEventBus.publishStructureChanged(
            scope: .space(targetSpaceID)
        )
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 4)

        inventoryCancellable.cancel()
        profileCancellable.cancel()
    }

    func testMountedPageTracksUnselectedLiveShortcutRegisterRekeyAndRetirement()
        async throws {
        let browserManager = BrowserManager()
        let registry = WindowRegistry()
        browserManager.windowRegistry = registry
        let window = BrowserWindowState()
        window.tabManager = browserManager.tabManager
        let space = browserManager.tabManager.spaceStateOwner.currentSpace
            ?? browserManager.tabManager.spaceServices.catalog.createSpace(
                name: "Mounted Live Shortcut"
            )
        window.currentSpaceId = space.id
        window.currentProfileId = space.profileId
        let selectedTab = browserManager.tabManager.regularTabLifecycleOwner
            .createNewTab(
                url: "about:blank",
                in: space,
                activate: false
            )
        window.currentTabId = selectedTab.id
        let unchangedSelection = selectedTab.id
        XCTAssertEqual(registry.register(window), .registered)
        defer { registry.unregister(window.id) }

        let context = WindowSidebarContext.make(
            browserManager: browserManager,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil })
        )
        let sourcePin = makeShortcutPin(
            title: "Mounted Source",
            spaceID: space.id
        )
        let targetPin = makeShortcutPin(
            title: "Mounted Target",
            spaceID: space.id
        )
        let current: @MainActor () -> [UUID] = {
            [sourcePin, targetPin].compactMap { pin in
                context.selection.liveTab(for: pin.id, in: window).map {
                    _ in pin.id
                }
            }
        }
        let model = SidebarScopedSnapshotModel(
            current: current,
            changes: context.inventoryUpdates.pageChanges(
                windowID: window.id,
                spaceID: space.id,
                profileID: space.profileId
            )
            .map { _ in current() }
            .eraseToAnyPublisher()
        )
        model.setActive(true)
        defer { model.setActive(false) }
        XCTAssertEqual(model.snapshot, [])

        let unrelatedWindow = BrowserWindowState()
        unrelatedWindow.tabManager = browserManager.tabManager
        unrelatedWindow.currentSpaceId = space.id
        unrelatedWindow.currentProfileId = space.profileId
        XCTAssertEqual(registry.register(unrelatedWindow), .registered)
        let unrelatedLiveTab = browserManager.tabManager.shortcutTabMaterializer
            .materialize(
                sourcePin,
                in: unrelatedWindow.id,
                currentSpaceId: space.id
            )
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot, [])
        browserManager.tabManager.tabClosureService.removeTab(
            unrelatedLiveTab.id
        )
        registry.unregister(unrelatedWindow.id)

        let liveTab = browserManager.tabManager.shortcutTabMaterializer.materialize(
            sourcePin,
            in: window.id,
            currentSpaceId: space.id
        )
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot, [sourcePin.id])
        XCTAssertEqual(window.currentTabId, unchangedSelection)

        XCTAssertTrue(
            browserManager.tabManager.shortcutTabBindings.rebind(
                liveTab,
                from: sourcePin,
                to: targetPin
            )
        )
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot, [targetPin.id])
        XCTAssertEqual(window.currentTabId, unchangedSelection)

        browserManager.tabManager.tabClosureService.removeTab(liveTab.id)
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot, [])
        XCTAssertEqual(window.currentTabId, unchangedSelection)
    }

    func testToolbarCommandsDoNotPublishWithoutManagerOrForUnpinnedOrder() {
        let surfaceStore = BrowserExtensionSurfaceStore(extensionManager: nil)
        var exactChanges = 0
        var broadChanges = 0
        let exact = surfaceStore.toolbarLayoutChanges(for: nil).sink {
            exactChanges += 1
        }
        let broad = surfaceStore.objectWillChange.sink {
            broadChanges += 1
        }
        let module = SumiExtensionsModule(
            surfaceStore: surfaceStore
        )

        module.pinToToolbar("extension-a")
        module.unpinFromToolbar("extension-a")
        module.movePinnedToolbarSlot(id: "extension-a", to: 0)
        module.moveUnpinnedExtension(
            id: "extension-a",
            to: 0,
            within: ["extension-a"]
        )

        XCTAssertEqual(exactChanges, 0)
        XCTAssertEqual(broadChanges, 0)
        withExtendedLifetime((exact, broad)) {}
    }

    func testToolbarCommandsPublishOncePerSuccessfulPinnedMutation() throws {
        let suiteName = "SumiTests.SidebarToolbarLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.enable(.extensions)
        let container = try makeInMemoryStartupModelContainer()
        let surfaceStore = BrowserExtensionSurfaceStore(extensionManager: nil)
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            surfaceStore: surfaceStore
        )
        var exactChanges = 0
        var broadChanges = 0
        let exact = surfaceStore.toolbarLayoutChanges(for: nil).sink {
            exactChanges += 1
        }
        let broad = surfaceStore.objectWillChange.sink {
            broadChanges += 1
        }

        module.pinToToolbar("extension-a")
        XCTAssertEqual(exactChanges, 1)

        module.pinToToolbar("extension-a")
        module.unpinFromToolbar("not-pinned")
        module.movePinnedToolbarSlot(id: "not-pinned", to: 0)
        module.moveUnpinnedExtension(
            id: "extension-a",
            to: 0,
            within: ["extension-a"]
        )
        XCTAssertEqual(exactChanges, 1)

        module.pinToToolbar("extension-b")
        module.movePinnedToolbarSlot(id: "extension-a", to: 1)
        XCTAssertEqual(exactChanges, 3)

        module.movePinnedToolbarSlot(id: "extension-a", to: 1)
        XCTAssertEqual(exactChanges, 3)

        module.unpinFromToolbar("extension-a")
        XCTAssertEqual(exactChanges, 4)
        XCTAssertEqual(broadChanges, 0)
        withExtendedLifetime((exact, broad)) {}
    }

    func testToolbarLayoutChangesOnlyReachAffectedProfile() {
        let surfaceStore = BrowserExtensionSurfaceStore(extensionManager: nil)
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        var firstChanges = 0
        var secondChanges = 0
        let first = surfaceStore.toolbarLayoutChanges(for: firstProfileID).sink {
            firstChanges += 1
        }
        let second = surfaceStore.toolbarLayoutChanges(for: secondProfileID).sink {
            secondChanges += 1
        }

        surfaceStore.publishToolbarLayoutChanged(for: firstProfileID)

        XCTAssertEqual(firstChanges, 1)
        XCTAssertEqual(secondChanges, 0)
        withExtendedLifetime((first, second)) {}
    }

    func testInstalledCatalogPublishesToolbarOnlyForLayoutRelevantProjection() async throws {
        let suiteName = "SumiTests.SidebarToolbarCatalog.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.enable(.extensions)
        let container = try makeInMemoryStartupModelContainer()
        let surfaceStore = BrowserExtensionSurfaceStore(extensionManager: nil)
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            surfaceStore: surfaceStore
        )
        let manager = try XCTUnwrap(module.managerForTesting())
        await drainMainActorTurns()
        var layoutChanges = 0
        let exact = surfaceStore.toolbarLayoutChanges(for: nil).sink {
            layoutChanges += 1
        }

        manager.installedExtensionCollection.upsert(
            makeToolbarExtension(version: "1.0", name: "Toolbar Action")
        )
        await drainMainActorTurns()
        XCTAssertEqual(layoutChanges, 1)

        manager.installedExtensionCollection.upsert(
            makeToolbarExtension(version: "2.0", name: "Toolbar Action")
        )
        await drainMainActorTurns()
        XCTAssertEqual(layoutChanges, 1)

        manager.installedExtensionCollection.upsert(
            makeToolbarExtension(version: "2.0", name: "Renamed Toolbar Action")
        )
        await drainMainActorTurns()
        XCTAssertEqual(layoutChanges, 2)
        withExtendedLifetime(exact) {}
    }

    func testURLBarDisplayModelIgnoresActionPolicyAndCatalogMetadata() async throws {
        let suiteName = "SumiTests.ActionButtonProjection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.enable(.extensions)
        let container = try makeInMemoryStartupModelContainer()
        let surfaceStore = BrowserExtensionSurfaceStore(extensionManager: nil)
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            surfaceStore: surfaceStore
        )
        let manager = try XCTUnwrap(module.managerForTesting())
        await drainMainActorTurns()
        manager.installedExtensionCollection.upsert(
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

        manager.actionStatesByExtensionID["unrelated-extension"] =
            makeActionState(extensionID: "unrelated-extension", label: "Other")
        surfaceStore.refreshSiteAccessPolicies(profileId: UUID())
        await drainMainActorTurns()
        XCTAssertEqual(displayChanges, 0)

        manager.installedExtensionCollection.upsert(
            makeToolbarExtension(version: "2.0", name: "Toolbar Action")
        )
        await drainMainActorTurns()
        XCTAssertEqual(displayChanges, 0)
        XCTAssertEqual(model.snapshot.extensions.first?.name, "Toolbar Action")

        manager.installedExtensionCollection.upsert(
            makeToolbarExtension(version: "2.0", name: "Renamed Action")
        )
        await drainMainActorTurns()
        XCTAssertEqual(displayChanges, 1)
        XCTAssertEqual(
            model.snapshot.extensions.first?.name,
            "Renamed Action"
        )
        module.pinToToolbar("toolbar-extension")
        await drainMainActorTurns()
        XCTAssertEqual(
            model.snapshot.pinnedExtensionIDs,
            ["toolbar-extension"]
        )
        module.unpinFromToolbar("toolbar-extension")
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot.pinnedExtensionIDs, [])

        manager.installedExtensionCollection.upsert(
            makeToolbarExtension(
                version: "2.0",
                name: "Renamed Action",
                isEnabled: false
            )
        )
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot.enabledExtensions, [])
        manager.installedExtensionCollection.upsert(
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
                pinnedExtensionIDs: ["mounted"]
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
        let container = try makeInMemoryStartupModelContainer()
        let surfaceStore = BrowserExtensionSurfaceStore(extensionManager: nil)
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            surfaceStore: surfaceStore
        )
        let manager = try XCTUnwrap(module.managerForTesting())
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
        manager.pinnedToolbarExtensionIDsByProfile = [
            ExtensionManager.pinnedToolbarProfileKey(
                for: sourceProfileID
            ): ids,
            ExtensionManager.pinnedToolbarProfileKey(
                for: destinationProfileID
            ): ids,
        ]
        let globalIcon = NSImage(size: NSSize(width: 9, height: 9))
        for id in ids {
            manager.actionStatesByExtensionID[id] =
                BrowserExtensionActionSurfaceState(
                    extensionID: id,
                    label: "Wrong Profile",
                    badgeText: "WRONG",
                    hasUnreadBadgeText: true,
                    isEnabled: true,
                    presentsPopup: false,
                    icon: globalIcon
                )
        }
        await drainMainActorTurns()
        let staticIcon = NSImage(size: NSSize(width: 3, height: 3))
        surfaceStore.iconCache.imageLoader = { _ in staticIcon }
        let sourceSlots = manager.orderedPinnedToolbarSlots(
            enabledExtensions: records,
            profileId: sourceProfileID
        )
        let destinationSlots = manager.orderedPinnedToolbarSlots(
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
        var snapshots = [
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
        ]
        let changes = PassthroughSubject<
            ExtensionActionPresentationChange,
            Never
        >()
        let model = BrowserExtensionActionButtonModel(
            changes: changes.eraseToAnyPublisher(),
            query: { snapshots[$0] }
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

        snapshots[targetA] = BrowserExtensionActionButtonSnapshot(
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
        let browserManager = BrowserManager(nowPlayingController: nowPlayingController)
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        windowRegistry.register(windowState)
        browserManager.windowRegistry = windowRegistry
        let viewContext = WindowSidebarContext.make(
            browserManager: browserManager,
            updaterService: updaterService
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
            nowPlayingController: nowPlayingController,
            updaterService: updaterService,
            resolvedThemeContext: .default,
            chromeBackgroundResolvedThemeContext: .default,
            windowChromeSize: CGSize(width: 320, height: 640),
            sidebarDragState: dragState
        )
        let root = SidebarColumnHostedRoot.view(
            environmentContext: environmentContext,
            presentationContext: .docked(sidebarWidth: 280),
            inventory: viewContext.inventory,
            selection: viewContext.selection,
            pinProjection: viewContext.pinProjection,
            pinCommands: viewContext.pinCommands,
            spaceLifecycle: viewContext.spaceLifecycle,
            regularTabs: viewContext.regularTabs,
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
        XCTAssertEqual(root.presentationContext, .docked(sidebarWidth: 280))
    }

    private func drainMainActorTurns() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    private func makeToolbarExtension(
        id: String = "toolbar-extension",
        version: String,
        name: String,
        isEnabled: Bool = true
    ) -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: name,
            version: version,
            manifestVersion: 3,
            description: "non-layout metadata",
            isEnabled: isEnabled,
            installDate: .distantPast,
            lastUpdateDate: .distantFuture,
            packagePath: "/tmp/toolbar-extension",
            iconPath: "/tmp/toolbar-extension/icon.png",
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: version,
            manifestRootFingerprint: version,
            sourceBundlePath: "/tmp/toolbar-extension",
            optionsPagePath: nil,
            defaultPopupPath: "popup.html",
            hasBackground: false,
            hasAction: true,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: true,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: true,
                hasOptionsPage: false,
                hasExtensionPages: true
            ),
            manifest: [
                "manifest_version": 3,
                "name": name,
                "version": version,
            ]
        )
    }

    private func makeActionState(
        extensionID: String,
        label: String
    ) -> BrowserExtensionActionSurfaceState {
        BrowserExtensionActionSurfaceState(
            extensionID: extensionID,
            label: label,
            badgeText: "",
            hasUnreadBadgeText: false,
            isEnabled: true,
            presentsPopup: false,
            icon: nil
        )
    }

    private func makeShortcutPin(
        title: String,
        spaceID: UUID
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceID,
            index: 0,
            launchURL: URL(
                string: "https://\(title.lowercased().replacingOccurrences(of: " ", with: "-")).example"
            )!,
            title: title
        )
    }

    private func makeActionTarget(
        extensionID: String,
        profileID: UUID,
        window: BrowserWindowState,
        registry: WindowRegistry,
        tab: Tab,
        context: NSObject,
        adapter: NSObject
    ) -> ExtensionActionPresentationTarget {
        let windowReceipt = registry.registrationReceipt(for: window)!
        return ExtensionActionPresentationTarget(
            extensionID: extensionID,
            profileID: profileID,
            windowID: window.id,
            windowIdentifier: ObjectIdentifier(window),
            windowRegistrationReceipt: windowReceipt,
            tabID: tab.id,
            tabIdentifier: ObjectIdentifier(tab),
            adapterIdentifier: ObjectIdentifier(adapter),
            contextReceipt: ExtensionContextBindingReceipt(
                key: .init(
                    profileId: profileID,
                    extensionId: extensionID
                ),
                contextIdentifier: ObjectIdentifier(context),
                bindingRevision: 1,
                controllerIdentifier: nil,
                controllerBindingRevision: 0
            ),
            window: window,
            tab: tab
        )
    }
}
