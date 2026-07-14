import Combine
import Foundation

@MainActor
extension WindowWebContentContext {
    static func make(
        browserManager: BrowserManager,
        updaterService: SumiUpdaterService,
        defaultBrowserService: SumiDefaultBrowserService
    ) -> WindowWebContentContext {
        WindowWebContentContext(
            browserContext: WebsiteViewContextFactory.websiteViewBrowserContext(
                for: browserManager
            ),
            nativeSurfaceRootBuilders: WebsiteViewContextFactory.nativeSurfaceRootBuilders(
                for: browserManager,
                updaterService: updaterService,
                defaultBrowserService: defaultBrowserService
            ),
            webViewOwnershipQuery: browserManager.webViewRuntime.ownershipQuery,
            trackedWebViewAdmission: browserManager.webViewRuntime.trackedWebViewAdmission,
            webViewCompositorRuntime: browserManager.webViewRuntime.compositorRuntime,
            webViewProtectionRuntime: browserManager.webViewRuntime.protectionRuntime
        )
    }
}

@MainActor
extension WindowSplitContext {
    static func make(browserManager: BrowserManager) -> WindowSplitContext {
        WindowSplitContext(
            updates: browserManager.splitComposition.updates,
            query: browserManager.splitComposition.query,
            previews: browserManager.splitComposition.previews,
            layout: browserManager.splitComposition.layout,
            drops: browserManager.splitComposition.drops,
            dropTargets: browserManager.splitComposition.dropTargets
        )
    }
}

@MainActor
extension WindowSidebarContext {
    static func make(
        browserManager: BrowserManager,
        updaterService: SumiUpdaterService
    ) -> WindowSidebarContext {
        let tabManager = browserManager.tabManager
        let currentProfileAuthority = browserManager.currentProfileAuthority
        let shellRuntime = browserManager.shellRuntime
        let sidebarPresentation = browserManager.chromeBundle.sidebarPresentationOwner
        let windowPersistence = browserManager.windowSessionBundle.persistence
        let themeEditor = browserManager.chromeBundle.workspaceThemeEditorOwner
        let runtimeIsAlive: @MainActor () -> Bool = { [weak tabManager] in
            tabManager != nil
        }
        let windowIdentity = SidebarWindowIdentityQuery(
            registry: { [weak shellRuntime] in shellRuntime?.windowRegistry }
        )
        let inventory = SidebarInventoryProjection(
            runtimeIsAlive: runtimeIsAlive,
            spaces: tabManager.spaceStateOwner,
            regularTabs: tabManager.regularTabCollectionStateOwner,
            folders: tabManager.folderCollectionStateOwner,
            pins: tabManager.shortcutPinCollectionStateOwner,
            splitGroups: tabManager.splitGroupStore,
            splitOrdering: tabManager.splitGroupSidebarOrdering
        )
        let selection = SidebarWindowSelectionQuery(
            runtimeIsAlive: runtimeIsAlive,
            windows: windowIdentity,
            windowTabs: browserManager.shellRuntime.windowTabs,
            shortcutPresentation: tabManager.shortcutPresentationOwner,
            splitQuery: browserManager.splitComposition.query
        )
        let pinProjection = SidebarPinFolderProjection(
            runtimeIsAlive: runtimeIsAlive,
            windows: windowIdentity,
            essentials: tabManager.essentialsShortcutPlacementOwner,
            resolution: tabManager.shortcutPinRuntimeResolutionOwner
        )
        let pinCommands = SidebarPinFolderCommands(
            runtimeIsAlive: runtimeIsAlive,
            windows: windowIdentity,
            pins: tabManager.shortcutPinCollectionStateOwner,
            folders: tabManager.folderCollectionStateOwner,
            structure: tabManager.spacePinnedStructureOwner,
            shortcutCommands: tabManager.shortcutPinCommandOwner,
            folderCommands: tabManager.folderMutationOwner,
            materializer: tabManager.shortcutTabMaterializer,
            profileAssignments: tabManager.profileAssignments.shortcuts
        )
        let spaceLifecycle = SidebarSpaceLifecycle(
            runtimeIsAlive: runtimeIsAlive,
            inventory: inventory,
            catalog: tabManager.spaceServices.catalog,
            removal: tabManager.spaceServices.removal
        )
        let shortcutInsertion = ShortcutURLInsertionService(
            store: tabManager.shortcutPinStoreOwner,
            materializer: tabManager.shortcutTabMaterializer,
            structuralLookup: tabManager.structuralLookupCoordinator,
            prepareActivation: { [weak browserManager] windowState in
                guard let browserManager,
                      browserManager.windowRegistry?.windows[windowState.id] === windowState
                else { return nil }
                return { [browserManager, windowState] tab in
                    browserManager.selectTab(tab, in: windowState)
                }
            },
            schedulePersistence: { [weak tabManager] in
                tabManager?.structuralPersistence.scheduleStructuralPersistence()
            }
        )
        let urlDrops = SidebarURLDropService(
            tabOpening: browserManager.tabLifecycleService.opening,
            nativeSurfaces: browserManager.chromeBundle.nativeSurfaceRoutingOwner,
            destinations: SidebarURLDropDestinationCatalog(
                spaces: tabManager.spaceStateOwner,
                folders: tabManager.folderCollectionStateOwner,
                essentials: tabManager.essentialsShortcutPlacementOwner
            ),
            shortcutInsertion: shortcutInsertion
        )
        let dragTransactions = SidebarDragTransactionPort(
            windows: windowIdentity,
            sourceInventory: SidebarDragSourceInventory(
                essentialPins: tabManager.shortcutPinCollectionStateOwner,
                splitOrdering: tabManager.splitGroupSidebarOrdering,
                regularTabs: tabManager.regularTabCollectionOwner,
                folders: tabManager.folderCollectionStateOwner,
                spacePinned: tabManager.spacePinnedStructureOwner
            ),
            dragOperations: tabManager.sidebarDragRouter,
            urlDropService: urlDrops
        )
        let inventoryUpdates = SidebarInventoryUpdates(
            changes: tabManager.tabStructureEventBus.scopedStructureChangesPublisher
        )
        let profileUpdates = SidebarProfileUpdates(
            profiles: browserManager.profileManager.$profiles.eraseToAnyPublisher(),
            runtime: Publishers.CombineLatest(
                currentProfileAuthority.$currentProfile,
                currentProfileAuthority.$isTransitioning
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
        return WindowSidebarContext(
            browserContext: SidebarBrowserContext.live(
                browserManager: browserManager,
                spaceLifecycle: spaceLifecycle
            ),
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            spaceLifecycle: spaceLifecycle,
            regularTabs: SidebarRegularTabsController.live(
                tabManager: tabManager,
                liveFolderManager: browserManager.liveFolderManager
            ),
            dragTransactions: dragTransactions,
            inventoryUpdates: inventoryUpdates,
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
            hostRecoveryCoordinator: browserManager.sidebarHostRecoveryCoordinator,
            updaterService: updaterService,
            currentProfileID: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile?.id
            },
            essentialPins: tabManager.shortcutPinCollectionStateOwner,
            hoverSidebarRuntime: BrowserHoverSidebarRuntimeFactory.runtime(
                for: browserManager
            )
        )
    }
}

@MainActor
extension WindowNativeModalContext {
    static func make(browserManager: BrowserManager) -> WindowNativeModalContext {
        let presentationOwner = browserManager.chromeBundle.nativeDialogPresentationOwner
        let profileManager = browserManager.profileManager
        let historyManager = browserManager.historyManager
        let websiteDataCleanupService = browserManager.dataServices
            .websiteDataCleanupService
        let currentProfileAuthority = browserManager.currentProfileAuthority

        return WindowNativeModalContext(
            presentationOwner: presentationOwner,
            browsingDataDialogContext: SumiBrowsingDataDialogContext(
                cleanupService: browserManager.browsingDataCleanupService,
                profileSnapshot: { [profileManager] in
                    profileManager.profiles
                },
                activeCleanupDependencies: {
                    [
                        currentProfileAuthority,
                        profileManager,
                        historyManager,
                        websiteDataCleanupService
                    ] in
                    guard currentProfileAuthority.currentProfile != nil else { return nil }
                    return BrowsingDataDialogCleanupDependencies(
                        historyManager: historyManager,
                        profiles: profileManager.profiles,
                        websiteDataCleanupService: websiteDataCleanupService
                    )
                },
                dismissNativeModalPresentation: { [presentationOwner] in
                    presentationOwner.dismissNativeModalPresentation()
                }
            )
        )
    }
}

@MainActor
extension WindowFindContext {
    static func make(browserManager: BrowserManager) -> WindowFindContext {
        WindowFindContext(manager: browserManager.findManager)
    }
}

@MainActor
extension WindowThemeChromeContext {
    static func make(browserManager: BrowserManager) -> WindowThemeChromeContext {
        WindowThemeChromeContext(
            spaces: browserManager.tabManager.spaceStateOwner,
            themeEditor: browserManager.chromeBundle.workspaceThemeEditorOwner,
            windowTabs: browserManager.shellRuntime.windowTabs
        )
    }
}

@MainActor
extension SidebarRegularTabsController {
    static func live(
        tabManager: TabManager,
        liveFolderManager: SumiLiveFolderManager
    ) -> SidebarRegularTabsController {
        SidebarRegularTabsController(
            dependencies: .live(
                tabManager: tabManager,
                liveFolderManager: liveFolderManager
            )
        )
    }
}

@MainActor
extension SidebarRegularTabsController.Dependencies {
    static func live(
        tabManager: TabManager,
        liveFolderManager: SumiLiveFolderManager
    ) -> Self {
        Self(
            spaces: { [weak tabManager] in
                tabManager?.spaceStateOwner.spaces ?? []
            },
            tabs: { [weak tabManager] space in
                tabManager?.regularTabCollectionOwner.tabs(in: space) ?? []
            },
            tab: { [weak tabManager] id in
                tabManager?.tabCollectionMembershipOwner.tab(for: id)
            },
            splitGroup: { [weak tabManager] memberID in
                tabManager?.splitGroupStore.group(containing: memberID)
            },
            shortcutPin: { [weak tabManager] id in
                tabManager?.shortcutPinCollectionStateOwner.shortcutPin(by: id)
            },
            folders: { [weak tabManager] spaceID in
                tabManager?.folderCollectionStateOwner.folders(for: spaceID) ?? []
            },
            isLiveFolder: { [weak liveFolderManager] folderID in
                liveFolderManager?.isLiveFolder(folderID) ?? false
            },
            canAddURLToEssentials: { [weak tabManager] url, context in
                tabManager?.essentialsShortcutPlacementOwner.canAddURL(
                    url,
                    using: context
                ) ?? false
            },
            clearRegularTabs: { [weak tabManager] spaceID in
                tabManager?.tabClosureService.clearRegularTabs(for: spaceID)
            },
            pinTabToSpace: { [weak tabManager] tab, spaceID in
                tabManager?.shortcutPinCommandOwner.pinTabToSpace(
                    tab,
                    spaceId: spaceID
                )
            },
            pinTabToEssentials: { [weak tabManager] tab, context in
                tabManager?.shortcutPinCommandOwner.pinTab(tab, context: context)
            },
            closeAllTabsBelow: { [weak tabManager] tab in
                tabManager?.tabClosureService.closeAllTabsBelow(tab)
            },
            moveTab: { [weak tabManager] tabID, targetSpaceID in
                tabManager?.sidebarDragRouter.moveTab(tabID, to: targetSpaceID)
            },
            moveTabToFolder: { [weak tabManager] tab, folderID in
                tabManager?.folderMutationOwner.moveTabToFolder(
                    tab: tab,
                    folderId: folderID
                )
            },
            assignTabToProfile: { [weak tabManager] tab, profileID in
                tabManager?.profileAssignments.tabs.assign(
                    tab,
                    toProfile: profileID
                ) ?? false
            }
        )
    }
}
