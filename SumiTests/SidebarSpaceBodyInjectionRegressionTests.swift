import AppKit
import Combine
import CoreGraphics
import class SwiftUI.NSHostingView
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
            changes: context.inventoryUpdates.launcherResidenceChanges(
                windowID: window.id,
                spaceID: space.id
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

    func testMountedPagePublishesBackgroundShortcutUnloadWhenInventoryIsUnchanged()
        throws {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: registry)
        let window = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: window)
        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(
                in: browserManager.spaceStateOwner,
                name: "Mounted Unload"
            )
        let selectedPin = makeShortcutPin(
            title: "Selected",
            spaceID: space.id
        )
        let backgroundPin = makeShortcutPin(
            title: "Background",
            spaceID: space.id
        )
        browserManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts(
                [selectedPin, backgroundPin],
                for: space.id
            )
        window.currentSpaceId = space.id
        window.currentProfileId = space.profileId
        XCTAssertEqual(registry.register(window), .registered)
        defer { registry.unregister(window.id) }
        let selectedTab = try XCTUnwrap(
            browserManager.shortcutTabMaterializer.materialize(
                selectedPin,
                in: window.id,
                currentSpaceId: space.id
            )
        )
        XCTAssertNotNil(
            browserManager.shortcutTabMaterializer.materialize(
                backgroundPin,
                in: window.id,
                currentSpaceId: space.id
            )
        )
        window.currentTabId = selectedTab.id
        window.currentShortcutPinId = selectedPin.id
        window.currentShortcutPinRole = selectedPin.role

        let context = WindowSidebarContext.make(
            browserManager: browserManager,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )
        let pinIDs = Set([selectedPin.id, backgroundPin.id])
        let current: @MainActor () -> SidebarLauncherRuntimeSnapshot = {
            context.selection.launcherRuntimeSnapshot(
                pinIDs: pinIDs,
                in: window
            )
        }
        let residenceChanges = context.inventoryUpdates.launcherResidenceChanges(
            windowID: window.id,
            spaceID: space.id
        )
        var residenceChangeCount = 0
        let residenceChangesCancellable = residenceChanges.sink { _ in
            residenceChangeCount += 1
        }
        var structuralPageChangeCount = 0
        let structuralPageChanges = context.inventoryUpdates.pageChanges(
            windowID: window.id,
            spaceID: space.id,
            profileID: space.profileId
        ).sink { _ in
            structuralPageChangeCount += 1
        }
        let model = SidebarScopedSnapshotModel(
            current: current,
            changes: residenceChanges.map { _ in current() }.eraseToAnyPublisher(),
            delivery: .mainActorImmediate(),
            areEquivalent: ==
        )
        model.setActive(true)
        defer { model.setActive(false) }
        var runtimePublicationCount = 0
        let publication = model.$snapshot.dropFirst().sink { _ in
            runtimePublicationCount += 1
        }
        XCTAssertNotNil(model.snapshot.liveTab(for: backgroundPin.id))
        XCTAssertFalse(
            context.selection.presentationState(
                for: backgroundPin,
                in: window
            ).shouldDesaturateIcon
        )

        context.browserContext.shortcutPinUnload.unloadShortcutPin(
            backgroundPin,
            in: window
        )

        XCTAssertNil(
            browserManager.shortcutPresentationOwner.shortcutLiveTab(
                for: backgroundPin.id,
                in: window.id
            )
        )
        XCTAssertTrue(
            context.selection.presentationState(
                for: backgroundPin,
                in: window
            ).shouldDesaturateIcon
        )
        XCTAssertNil(model.snapshot.liveTab(for: backgroundPin.id))
        XCTAssertEqual(residenceChangeCount, 1)
        XCTAssertEqual(runtimePublicationCount, 1)
        XCTAssertEqual(structuralPageChangeCount, 0)
        withExtendedLifetime((
            residenceChangesCancellable,
            structuralPageChanges,
            publication
        )) {}
    }

    func testMountedSidebarRendersBackgroundShortcutAsUnloadedWithoutAnotherEvent()
        async throws {
        let nowPlayingController = SumiNativeNowPlayingController()
        let updaterService = SumiUpdaterService(backendFactory: { _ in nil })
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            nowPlayingController: nowPlayingController
        )
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Mounted Visual Unload"
        )
        let selectedPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://selected-visual.example")!,
            title: "Selected Visual",
            iconAsset: "🟠"
        )
        let backgroundPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 1,
            launchURL: URL(string: "https://background-visual.example")!,
            title: "Background Visual"
        )
        browserManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts(
                [selectedPin, backgroundPin],
                for: space.id
            )

        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = space.profileId
        windowState.sidebarWidth = 280
        windowState.sidebarContentWidth = BrowserWindowState
            .sidebarContentWidth(for: 280)
        XCTAssertEqual(registry.register(windowState), .registered)
        registry.setActive(windowState)
        defer { registry.unregister(windowState.id) }

        let selectedTab = try XCTUnwrap(
            browserManager.shortcutTabMaterializer.materialize(
                selectedPin,
                in: windowState.id,
                currentSpaceId: space.id
            )
        )
        let backgroundTab = try XCTUnwrap(
            browserManager.shortcutTabMaterializer.materialize(
                backgroundPin,
                in: windowState.id,
                currentSpaceId: space.id
            )
        )
        backgroundTab.faviconPresentation = .bitmap(
            NSImage(size: NSSize(width: 16, height: 16), flipped: false) {
                rect in
                NSColor.systemOrange.setFill()
                rect.fill()
                return true
            }
        )
        backgroundTab.faviconIsTemplateGlobePlaceholder = false
        windowState.currentTabId = selectedTab.id
        windowState.currentShortcutPinId = selectedPin.id
        windowState.currentShortcutPinRole = selectedPin.role

        let viewContext = WindowSidebarContext.make(
            browserManager: browserManager,
            updaterService: updaterService,
            nowPlayingController: nowPlayingController
        )
        let dragState = SidebarDragState()
        let settingsSuiteName = "SumiTests.mountedVisualUnload.\(UUID().uuidString)"
        let settingsDefaults = try XCTUnwrap(
            UserDefaults(suiteName: settingsSuiteName)
        )
        defer {
            settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
        }
        let environmentContext = SidebarHostEnvironmentContext(
            browserContext: viewContext.browserContext,
            hostActions: viewContext.hostActions,
            windowState: windowState,
            windowRegistry: registry,
            sumiSettings: SumiSettingsService(userDefaults: settingsDefaults),
            keyboardShortcutManager: KeyboardShortcutManager(
                installEventMonitor: false
            ),
            nowPlayingController: nowPlayingController,
            updaterService: updaterService,
            resolvedThemeContext: .default,
            chromeBackgroundResolvedThemeContext: .default,
            windowChromeSize: CGSize(width: 280, height: 640),
            sidebarDragState: dragState
        )
        let root = SidebarColumnHostedRoot.view(
            environmentContext: environmentContext,
            presentationContext: .docked(sidebarWidth: 280),
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
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(x: 0, y: 0, width: 280, height: 640)
        let hostWindow = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        hostWindow.contentView = host

        await drainMainActorTurns()
        hostWindow.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        let loadedColorCount = try colorfulPixelCount(in: host)

        viewContext.browserContext.shortcutPinUnload.unloadShortcutPin(
            backgroundPin,
            in: windowState
        )

        await drainMainActorTurns()
        hostWindow.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        let unloadedColorCount = try colorfulPixelCount(in: host)

        XCTAssertNil(
            browserManager.shortcutPresentationOwner.shortcutLiveTab(
                for: backgroundPin.id,
                in: windowState.id
            )
        )
        XCTAssertLessThan(
            unloadedColorCount,
            loadedColorCount - 20,
            "The mounted background launcher icon must desaturate on the unload publication itself"
        )
        withExtendedLifetime(hostWindow) {}
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
        let firstSameProfile = context.inventoryUpdates.launcherResidenceChanges(
            windowID: window.id,
            spaceID: firstSameProfileSpace.id
        ).sink { _ in firstSameProfileChanges += 1 }
        let presentation = context.inventoryUpdates.launcherResidenceChanges(
            windowID: window.id,
            spaceID: presentationSpace.id
        ).sink { _ in presentationChanges += 1 }
        let execution = context.inventoryUpdates.launcherResidenceChanges(
            windowID: window.id,
            spaceID: executionSpace.id
        ).sink { _ in executionChanges += 1 }
        let unrelated = context.inventoryUpdates.launcherResidenceChanges(
            windowID: unrelatedWindowID,
            spaceID: presentationSpace.id
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
        module.movePinnedToolbarSlot(
            id: "extension-a",
            to: 0,
            within: ["extension-a"],
            profileId: nil
        )
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
        let container = try makeInMemoryStartupDatabase()
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
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
        module.movePinnedToolbarSlot(
            id: "not-pinned",
            to: 0,
            within: ["not-pinned"],
            profileId: nil
        )
        module.moveUnpinnedExtension(
            id: "extension-a",
            to: 0,
            within: ["extension-a"],
            profileId: nil
        )
        XCTAssertEqual(exactChanges, 1)

        module.pinToToolbar("extension-b", profileId: nil)
        module.movePinnedToolbarSlot(
            id: "extension-a",
            to: 1,
            within: ["extension-a", "extension-b"],
            profileId: nil
        )
        XCTAssertEqual(exactChanges, 3)

        module.movePinnedToolbarSlot(
            id: "extension-a",
            to: 1,
            within: ["extension-a", "extension-b"],
            profileId: nil
        )
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
        let container = try makeInMemoryStartupDatabase()
        let surfaceStore = BrowserExtensionSurfaceStore(binding: nil)
        var inspection: ExtensionManagerTestInspection?
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            initialProfileProvider: { profileA },
            managerFactory: { context, profile, configuration, registry in
                ExtensionManager(
            database: context,
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
        module.movePinnedToolbarSlot(
            id: "one",
            to: 1,
            within: ["one", "two"],
            profileId: profileB.id
        )
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
            database: container,
            currentProfileId: { profileA.id },
            installedExtensionIDs: { [] },
            publishedPinnedIDs: { [] },
            setPublishedPinnedIDs: { _ in }
        )
        XCTAssertEqual(reopenedPins.pinnedToolbarExtensionIDs(profileId: profileA.id), [])
        XCTAssertEqual(reopenedPins.pinnedToolbarExtensionIDs(profileId: profileB.id), ["one"])
        let reopenedHub = ExtensionHubOrderingOwner(database: container)
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

    func shortcutBindings(
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

    func drainMainActorTurns() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    func colorfulPixelCount(
        in host: NSView
    ) throws -> Int {
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB),
                    color.alphaComponent > 0.5
                else { continue }
                let maximum = max(
                    color.redComponent,
                    color.greenComponent,
                    color.blueComponent
                )
                let minimum = min(
                    color.redComponent,
                    color.greenComponent,
                    color.blueComponent
                )
                if maximum - minimum > 0.2 {
                    count += 1
                }
            }
        }
        return count
    }

    func makeToolbarExtension(
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

    func makeActionState(
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

    func attachBrowserRuntime(
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

    func makeShortcutPin(
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

    func makeActionTarget(
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
final class ExtensionActionSnapshotQueryOracle {
    typealias Snapshots = [
        ExtensionActionPresentationTarget: BrowserExtensionActionButtonSnapshot
    ]

    var snapshots: Snapshots

    init(_ snapshots: Snapshots) {
        self.snapshots = snapshots
    }
}
