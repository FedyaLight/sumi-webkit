import Combine
import Foundation

@MainActor
extension BrowserManager {
    func composeWindowSidebarContext(
        updaterService: SumiUpdaterService,
        nowPlayingController: SumiNativeNowPlayingController
    ) -> WindowSidebarContext {
        let shell = shellRuntime
        let profileAuthority = currentProfileAuthority
        let runtimeConnection = runtimePortConnection
        let runtimeIsAlive: @MainActor () -> Bool = { [runtimeConnection] in
            runtimeConnection.current != nil
        }
        let windowIdentity = SidebarWindowIdentityQuery(
            registry: shell.windowRegistry
        )
        let spaceCatalogProjection = SidebarSpaceCatalogProjection(
            runtime: runtimeConnection,
            spaces: spaceStateOwner,
            pins: shortcutPinCollectionStateOwner
        )
        let pinnedInventory = SidebarPinnedInventoryProjection(
            folders: folderCollectionStateOwner,
            pins: shortcutPinCollectionStateOwner,
            splitGroups: splitGroupStore,
            splitOrdering: splitGroupSidebarOrdering,
            folderExpansionChanges: tabStructureEventBus.folderExpansionChangesPublisher
        )
        let inventory = SidebarSpaceInventoryProjection(
            runtime: runtimeConnection,
            spaces: spaceStateOwner,
            regularTabs: regularTabCollectionOwner,
            pinned: pinnedInventory
        )
        let selection = SidebarWindowSelectionQuery(
            runtimeIsAlive: runtimeIsAlive,
            windows: windowIdentity,
            windowTabs: shell.windowTabs,
            shortcutPresentation: shortcutPresentationOwner,
            splitQuery: splitQuery
        )
        let pinProjection = SidebarPinFolderProjection(
            runtimeIsAlive: runtimeIsAlive,
            windows: windowIdentity,
            essentials: essentialsShortcutPlacementOwner,
            resolution: shortcutPinRuntimeResolutionOwner
        )
        let pinCommands = sidebarPinCommands
        let pinExecution = SidebarPinExecutionCommands(
            runtime: runtimeConnection,
            windows: windowIdentity,
            pins: shortcutPinCollectionStateOwner,
            materializer: shortcutTabMaterializer,
            profiles: shortcutExecutionProfileAssignments
        )
        let folderCommands = sidebarFolderCommands
        let spaceLifecycle = sidebarSpaceLifecycle
        let persistence = structuralPersistence
        let shortcutInsertion = ShortcutURLInsertionService(
            transaction: ShortcutURLInsertionTransaction(
                store: shortcutPinStoreOwner,
                activation: shortcutPresentationActivation,
                structuralMutations: structuralCollectionMutationOwner,
                structuralLookup: structuralLookupCoordinator,
                folderOpenState: folderOpenState
            ),
            prepareActivation: { [windowIdentity, selection = browserTabSelection]
                windowState in
                guard windowIdentity.contains(windowState) else { return nil }
                return { [selection, windowState] tab in
                    _ = selection.requestUserTabActivation(
                        tab,
                        in: windowState,
                        loadPolicy: .immediate
                    )
                }
            },
            schedulePersistence: { [persistence] in
                persistence.scheduleStructuralPersistence()
            }
        )
        let urlDrops = SidebarURLDropService(
            pageOpening: SidebarURLDropTabOpening(
                tabOpening: tabOpening,
                nativeSurfaces: chromeBundle.nativeSurfaceRoutingOwner
            ),
            destinations: SidebarURLDropDestinationCatalog(
                spaces: spaceStateOwner,
                folders: folderCollectionStateOwner,
                essentials: essentialsShortcutPlacementOwner
            ),
            shortcutInsertion: shortcutInsertion,
            orderProjection: SidebarDropOrderProjection(
                regularTabs: regularTabCollectionOwner,
                splitOrdering: splitGroupSidebarOrdering
            )
        )
        let dragTransactions = SidebarDragTransactionPort(
            windows: windowIdentity,
            dragOperations: sidebarDragRouter,
            urlDropService: urlDrops,
            splitPairing: SidebarSplitPairingTransaction(
                splitDrops: splitDrops
            )
        )
        let profileManager = profileManager
        let profileUpdates = SidebarProfileUpdates(
            profiles: profileManager.$profiles.eraseToAnyPublisher(),
            runtime: Publishers.CombineLatest(
                profileAuthority.$currentProfile,
                profileAuthority.$isTransitioning
            )
            .map { profile, isTransitioning in
                SidebarProfileRuntimeSnapshot(
                    currentProfileID: profile?.id,
                    isTransitioning: isTransitioning
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
        )
        let sidebarPresentation = chromeBundle.sidebarPresentationOwner
        let windowPersistence = windowSessionPersistenceCoordinator
        let themeEditor = chromeBundle.workspaceThemeEditorOwner

        return WindowSidebarContext(
            nowPlayingController: nowPlayingController,
            browserContext: composeSidebarBrowserContext(
                spaceLifecycle: spaceLifecycle
            ),
            spaceCatalog: spaceCatalogProjection,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            spaceLifecycle: spaceLifecycle,
            regularTabCatalog: composeSidebarRegularTabCatalog(),
            regularTabTargets: composeSidebarRegularTabTargetQuery(),
            regularTabLifecycleCommands:
                composeSidebarRegularTabLifecycleCommands(),
            regularTabShortcutCommands:
                composeSidebarRegularTabShortcutCommands(),
            regularTabPlacementCommands:
                composeSidebarRegularTabPlacementCommands(),
            dragTransactions: dragTransactions,
            inventoryUpdates: SidebarInventoryUpdates(
                changes: tabStructureEventBus.scopedStructureChangesPublisher
            ),
            profileUpdates: profileUpdates,
            hostActions: SidebarHostActions(
                updateSidebarWidth: { [sidebarPresentation] width, windowState, persist in
                    sidebarPresentation.updateSidebarWidth(
                        width,
                        for: windowState,
                        persist: persist
                    )
                },
                persistWindowSession: { [windowPersistence] windowState in
                    windowPersistence.persist(windowState)
                },
                dismissThemePickerCommittingIfNeeded: { [themeEditor] in
                    themeEditor.dismissThemePickerCommittingIfNeeded()
                }
            ),
            hostRecoveryCoordinator: sidebarHostRecoveryCoordinator,
            updaterService: updaterService,
            currentProfileID: { [profileAuthority] in
                profileAuthority.currentProfile?.id
            },
            hoverSidebarRuntime: composeSidebarHoverRuntime()
        )
    }

    func composeWindowThemeChromeContext() -> WindowThemeChromeContext {
        WindowThemeChromeContext(
            spaces: spaceStateOwner,
            themeEditor: chromeBundle.workspaceThemeEditorOwner,
            windowTabs: shellRuntime.windowTabs
        )
    }
}
