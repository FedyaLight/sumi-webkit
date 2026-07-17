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
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
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

        browserManager.tabStructureEventBus.publishStructureChanged(
            scope: .space(unrelatedSpaceID)
        )
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 3)

        browserManager.tabStructureEventBus.publishStructureChanged(
            scope: .space(targetSpaceID)
        )
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 4)

        inventoryCancellable.cancel()
        profileCancellable.cancel()
    }

    func testMountedPageTracksUnselectedLiveShortcutRegisterRekeyAndRetirement()
        async throws {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: registry)
        let window = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: window)
        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(
                in: browserManager.spaceStateOwner,
                name: "Mounted Live Shortcut"
            )
        window.currentSpaceId = space.id
        window.currentProfileId = space.profileId
        let selectedTab = browserManager.regularTabLifecycleOwner
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
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
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
        browserManager.tabResidenceAuthority.establishResidenceSession(on: unrelatedWindow)
        unrelatedWindow.currentSpaceId = space.id
        unrelatedWindow.currentProfileId = space.profileId
        XCTAssertEqual(registry.register(unrelatedWindow), .registered)
        let unrelatedLiveTab = try XCTUnwrap(
            browserManager.shortcutTabMaterializer.materialize(
                sourcePin,
                in: unrelatedWindow.id,
                currentSpaceId: space.id
            )
        )
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot, [])
        browserManager.tabClosureService.removeTab(
            unrelatedLiveTab.id
        )
        registry.unregister(unrelatedWindow.id)

        let liveTab = browserManager.shortcutTabMaterializer.materialize(
            sourcePin,
            in: window.id,
            currentSpaceId: space.id
        )!
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot, [sourcePin.id])
        XCTAssertEqual(window.currentTabId, unchangedSelection)

        XCTAssertTrue(
            shortcutBindings(for: browserManager).rebind(
                liveTab,
                from: sourcePin,
                to: targetPin
            )
        )
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot, [targetPin.id])
        XCTAssertEqual(window.currentTabId, unchangedSelection)

        browserManager.tabClosureService.removeTab(liveTab.id)
        await drainMainActorTurns()
        XCTAssertEqual(model.snapshot, [])
        XCTAssertEqual(window.currentTabId, unchangedSelection)
    }

    func testLiveShortcutEventsRetainAndRelocateExactPresentationPage()
        async throws {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let tabManager = browserManager
        let presentationProfile = try browserManager.profileManager.createProfile(
            name: "Presentation"
        )
        let executionProfile = try browserManager.profileManager.createProfile(
            name: "Execution"
        )
        let presentationProfileID = presentationProfile.id
        let executionProfileID = executionProfile.id
        let firstSameProfileSpace = installTestSpace(
            in: tabManager.spaceStateOwner,
            name: "Same Profile A",
            profileID: presentationProfileID
        )
        let presentationSpace = installTestSpace(
            in: tabManager.spaceStateOwner,
            name: "Presentation B",
            profileID: presentationProfileID
        )
        let executionSpace = installTestSpace(
            in: tabManager.spaceStateOwner,
            name: "Execution C",
            profileID: executionProfileID
        )
        tabManager.spaceStateOwner.replaceCurrentSpace(presentationSpace)
        let window = BrowserWindowState()
        window.currentSpaceId = presentationSpace.id
        window.currentProfileId = presentationProfileID
        let selectedTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "about:blank",
            in: presentationSpace,
            activate: false
        )
        window.currentTabId = selectedTab.id
        XCTAssertEqual(windowRegistry.register(window), .registered)
        defer {
            windowRegistry.unregister(window.id)
        }
        let unrelatedWindowID = UUID()
        var firstSameProfileChanges = 0
        var presentationChanges = 0
        var executionChanges = 0
        var unrelatedChanges = 0
        let context = WindowSidebarContext.make(
            browserManager: browserManager,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )
        let firstSameProfile = context.inventoryUpdates.pageChanges(
            windowID: window.id,
            spaceID: firstSameProfileSpace.id,
            profileID: presentationProfileID
        ).sink { _ in firstSameProfileChanges += 1 }
        let presentation = context.inventoryUpdates.pageChanges(
            windowID: window.id,
            spaceID: presentationSpace.id,
            profileID: presentationProfileID
        ).sink { _ in presentationChanges += 1 }
        let execution = context.inventoryUpdates.pageChanges(
            windowID: window.id,
            spaceID: executionSpace.id,
            profileID: executionProfileID
        ).sink { _ in executionChanges += 1 }
        let unrelated = context.inventoryUpdates.pageChanges(
            windowID: unrelatedWindowID,
            spaceID: presentationSpace.id,
            profileID: presentationProfileID
        ).sink { _ in unrelatedChanges += 1 }
        let sourceEssential = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: presentationProfileID,
            executionProfileId: executionProfileID,
            spaceId: nil,
            index: 0,
            launchURL: URL(string: "https://essential-source.example")!,
            title: "Essential Source"
        )
        let targetEssential = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: presentationProfileID,
            executionProfileId: executionProfileID,
            spaceId: nil,
            index: 0,
            launchURL: URL(string: "https://essential-target.example")!,
            title: "Essential Target"
        )
        let accountFork = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            executionProfileId: executionProfileID,
            spaceId: presentationSpace.id,
            index: 0,
            launchURL: URL(string: "https://account-fork.example")!,
            title: "Account Fork"
        )

        let essentialTab = tabManager.shortcutTabMaterializer.materialize(
            sourceEssential,
            in: window.id,
            currentSpaceId: presentationSpace.id
        )!
        XCTAssertNil(essentialTab.spaceId)
        XCTAssertEqual(essentialTab.profileId, executionProfileID)
        XCTAssertEqual(firstSameProfileChanges, 0)
        XCTAssertEqual(presentationChanges, 1)
        XCTAssertTrue(shortcutBindings(for: tabManager).rebind(
            essentialTab,
            from: sourceEssential,
            to: targetEssential
        ))
        XCTAssertEqual(firstSameProfileChanges, 0)
        XCTAssertEqual(presentationChanges, 2)

        XCTAssertIdentical(
            tabManager.shortcutTabMaterializer.materialize(
                targetEssential,
                in: window.id,
                currentSpaceId: firstSameProfileSpace.id
            ),
            essentialTab
        )
        XCTAssertEqual(firstSameProfileChanges, 1)
        XCTAssertEqual(presentationChanges, 3)
        tabManager.tabClosureService.removeTab(essentialTab.id)
        XCTAssertEqual(firstSameProfileChanges, 2)
        XCTAssertEqual(presentationChanges, 3)

        let accountForkTab = tabManager.shortcutTabMaterializer.materialize(
            accountFork,
            in: window.id,
            currentSpaceId: presentationSpace.id
        )!
        XCTAssertEqual(accountForkTab.spaceId, presentationSpace.id)
        XCTAssertEqual(accountForkTab.profileId, executionProfileID)
        XCTAssertEqual(presentationChanges, 4)
        tabManager.tabClosureService.removeTab(accountForkTab.id)
        XCTAssertEqual(presentationChanges, 5)
        XCTAssertEqual(firstSameProfileChanges, 2)

        let unpresentedPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: presentationProfileID,
            index: 0,
            launchURL: URL(string: "https://no-presentation.example")!,
            title: "No Presentation"
        )
        XCTAssertNil(
            tabManager.shortcutTabMaterializer.materialize(
                unpresentedPin,
                in: window.id,
                currentSpaceId: nil
            )
        )
        XCTAssertNil(
            tabManager.liveShortcutTabs.tab(
                for: unpresentedPin.id,
                in: window.id
            )
        )
        XCTAssertEqual(presentationChanges, 5)
        XCTAssertEqual(firstSameProfileChanges, 2)
        XCTAssertEqual(executionChanges, 0)
        XCTAssertEqual(unrelatedChanges, 0)
        XCTAssertEqual(window.currentTabId, selectedTab.id)
        await drainMainActorTurns()
        withExtendedLifetime((
            firstSameProfile,
            presentation,
            execution,
            unrelated
        )) {}
    }

    func testToolbarCommandsDoNotPublishWithoutManagerOrForUnpinnedOrder() {
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
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

        module.pinToToolbar("extension-a", profileId: nil)
        module.unpinFromToolbar("extension-a", profileId: nil)
        module.movePinnedToolbarSlot(id: "extension-a", to: 0, profileId: nil)
        module.moveUnpinnedExtension(
            id: "extension-a",
            to: 0,
            within: ["extension-a"],
            profileId: nil
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
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            surfaceStore: surfaceStore
        )
        let browserRuntime = attachBrowserRuntime(to: module)
        defer { withExtendedLifetime(browserRuntime) {} }
        var exactChanges = 0
        var broadChanges = 0
        let exact = surfaceStore.toolbarLayoutChanges(for: nil).sink {
            exactChanges += 1
        }
        let broad = surfaceStore.objectWillChange.sink {
            broadChanges += 1
        }

        module.pinToToolbar("extension-a", profileId: nil)
        XCTAssertEqual(exactChanges, 1)

        module.pinToToolbar("extension-a", profileId: nil)
        module.unpinFromToolbar("not-pinned", profileId: nil)
        module.movePinnedToolbarSlot(id: "not-pinned", to: 0, profileId: nil)
        module.moveUnpinnedExtension(
            id: "extension-a",
            to: 0,
            within: ["extension-a"],
            profileId: nil
        )
        XCTAssertEqual(exactChanges, 1)

        module.pinToToolbar("extension-b", profileId: nil)
        module.movePinnedToolbarSlot(id: "extension-a", to: 1, profileId: nil)
        XCTAssertEqual(exactChanges, 3)

        module.movePinnedToolbarSlot(id: "extension-a", to: 1, profileId: nil)
        XCTAssertEqual(exactChanges, 3)

        module.unpinFromToolbar("extension-a", profileId: nil)
        XCTAssertEqual(exactChanges, 4)
        XCTAssertEqual(broadChanges, 0)
        withExtendedLifetime((exact, broad)) {}
    }

    func testToolbarMutationsPersistAndPublishForRenderedProfile() throws {
        let suiteName = "SumiTests.RenderedToolbarProfile.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let moduleDefaults = try XCTUnwrap(
            UserDefaults(suiteName: "\(suiteName).module")
        )
        defer { moduleDefaults.removePersistentDomain(forName: "\(suiteName).module") }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: moduleDefaults)
        )
        registry.enable(.extensions)
        let profileA = Profile(name: "Current A")
        let profileB = Profile(name: "Rendered B")
        let container = try makeInMemoryStartupModelContainer()
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
        var inspection: ExtensionManagerTestInspection?
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            initialProfileProvider: { profileA },
            managerFactory: { context, profile, configuration, registry in
                ExtensionManager(
                    context: context,
                    initialProfile: profile,
                    browserConfiguration: configuration,
                    moduleRegistry: registry,
                    extensionPreferences: preferences,
                    testInspectionDidAssemble: { inspection = $0 }
                )
            },
            surfaceStore: surfaceStore
        )
        let browserRuntime = attachBrowserRuntime(
            to: module,
            currentProfile: profileA
        )
        defer { withExtendedLifetime(browserRuntime) {} }
        _ = module.managerForTesting()
        let roles = try XCTUnwrap(inspection)
        XCTAssertEqual(roles.contextState.profiles.currentProfileId, profileA.id)
        var currentChanges = 0
        var renderedChanges = 0
        let current = surfaceStore.toolbarLayoutChanges(for: profileA.id).sink {
            currentChanges += 1
        }
        let rendered = surfaceStore.toolbarLayoutChanges(for: profileB.id).sink {
            renderedChanges += 1
        }

        module.pinToToolbar("one", profileId: profileB.id)
        module.pinToToolbar("two", profileId: profileB.id)
        module.movePinnedToolbarSlot(id: "one", to: 1, profileId: profileB.id)
        module.unpinFromToolbar("two", profileId: profileB.id)
        module.moveUnpinnedExtension(
            id: "hub-one",
            to: 1,
            within: ["hub-one", "hub-two"],
            profileId: profileB.id
        )

        XCTAssertEqual(currentChanges, 0)
        XCTAssertEqual(renderedChanges, 5)
        XCTAssertEqual(roles.actionSurfaces.publication.pinnedToolbarExtensionIDs, [])
        XCTAssertEqual(
            roles.actionSurfaces.toolbarPinning.pinnedToolbarExtensionIDs(
                profileId: profileA.id
            ),
            []
        )
        XCTAssertEqual(
            roles.actionSurfaces.toolbarPinning.pinnedToolbarExtensionIDs(
                profileId: profileB.id
            ),
            ["one"]
        )
        let reopenedPins = ExtensionToolbarPinningOwner(
            preferences: preferences,
            currentProfileId: { profileA.id },
            installedExtensionIDs: { [] },
            publishedPinnedIDs: { [] },
            setPublishedPinnedIDs: { _ in }
        )
        XCTAssertEqual(reopenedPins.pinnedToolbarExtensionIDs(profileId: profileA.id), [])
        XCTAssertEqual(reopenedPins.pinnedToolbarExtensionIDs(profileId: profileB.id), ["one"])
        let reopenedHub = ExtensionHubOrderingOwner(preferences: preferences)
        XCTAssertEqual(
            reopenedHub.orderedUnpinnedExtensionIDs(
                candidateIDs: ["hub-one", "hub-two"],
                profileId: profileA.id
            ),
            ["hub-one", "hub-two"]
        )
        XCTAssertEqual(
            reopenedHub.orderedUnpinnedExtensionIDs(
                candidateIDs: ["hub-one", "hub-two"],
                profileId: profileB.id
            ),
            ["hub-two", "hub-one"]
        )
        withExtendedLifetime((current, rendered)) {}
    }

    func testToolbarLayoutChangesOnlyReachAffectedProfile() {
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
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
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
        var inspection: ExtensionManagerTestInspection?
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            managerFactory: { context, profile, configuration, registry in
                ExtensionManager(
                    context: context,
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
        let installedExtensions = try XCTUnwrap(inspection)
            .actionSurfaces.installedExtensions
        await drainMainActorTurns()
        var layoutChanges = 0
        let exact = surfaceStore.toolbarLayoutChanges(for: nil).sink {
            layoutChanges += 1
        }

        installedExtensions.upsert(
            makeToolbarExtension(version: "1.0", name: "Toolbar Action")
        )
        await drainMainActorTurns()
        XCTAssertEqual(layoutChanges, 1)

        installedExtensions.upsert(
            makeToolbarExtension(version: "2.0", name: "Toolbar Action")
        )
        await drainMainActorTurns()
        XCTAssertEqual(layoutChanges, 1)

        installedExtensions.upsert(
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
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
        var inspection: ExtensionManagerTestInspection?
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            managerFactory: { context, profile, configuration, registry in
                ExtensionManager(
                    context: context,
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
        let container = try makeInMemoryStartupModelContainer()
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
        var inspection: ExtensionManagerTestInspection?
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            managerFactory: { context, profile, configuration, registry in
                ExtensionManager(
                    context: context,
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

    private func shortcutBindings(
        for browser: BrowserManager
    ) -> ShortcutTabBindingSynchronizer {
        let targets = ShortcutTabBindingTargetMutationService(
            resolution: browser.shortcutPinRuntimeResolutionOwner,
            profiles: browser.tabProfileTransitions
        )
        return ShortcutTabBindingSynchronizer(
            presentationRefreshes: browser.liveShortcutPresentationRefreshes,
            runtimeMutations: ShortcutTabBindingRuntimeMutation(
                registry: browser.liveShortcutTabs,
                targets: targets,
                runtimeConnection: browser.runtimePortConnection,
                windowMutations: browser.shortcutWindowMutationOwner,
                structuralLookup: browser.structuralLookupCoordinator
            ),
            targets: targets
        )
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

    private func attachBrowserRuntime(
        to module: SumiExtensionsModule,
        currentProfile: Profile? = nil
    ) -> BrowserManager {
        let browserManager = BrowserManager()
        browserManager.currentProfile = currentProfile
        module.attach(
            runtime: BrowserExtensionsModuleRuntimeFactory.runtime(
                for: browserManager
            )
        )
        return browserManager
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

@MainActor
private final class ExtensionActionSnapshotQueryOracle {
    typealias Snapshots = [
        ExtensionActionPresentationTarget: BrowserExtensionActionButtonSnapshot
    ]

    var snapshots: Snapshots

    init(_ snapshots: Snapshots) {
        self.snapshots = snapshots
    }
}
