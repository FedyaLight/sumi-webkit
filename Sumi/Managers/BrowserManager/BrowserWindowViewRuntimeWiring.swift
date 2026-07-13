import Combine
import Foundation

@MainActor
extension WindowViewBrowserContext {
    static func make(
        browserManager: BrowserManager,
        updaterService: SumiUpdaterService,
        defaultBrowserService: SumiDefaultBrowserService
    ) -> WindowViewBrowserContext {
        let tabManager = browserManager.tabManager
        let runtimeIsAlive: @MainActor () -> Bool = { [weak tabManager] in
            tabManager != nil
        }
        let windowIdentity = SidebarWindowIdentityQuery(
            registry: { [weak browserManager] in browserManager?.windowRegistry }
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
        let dragInventory = SidebarDragSourceInventory(
            essentialPins: tabManager.shortcutPinCollectionStateOwner,
            splitOrdering: tabManager.splitGroupSidebarOrdering,
            regularTabs: tabManager.regularTabCollectionOwner,
            folders: tabManager.folderCollectionStateOwner,
            spacePinned: tabManager.spacePinnedStructureOwner
        )
        let dragTransactions = SidebarDragTransactionPort(
            windows: windowIdentity,
            sourceInventory: dragInventory,
            dragOperations: tabManager.sidebarDragRouter,
            urlDropService: urlDrops
        )
        let updateStreams = SidebarUpdateStreams(
            inventoryRevision: browserManager.$tabStructuralRevision.eraseToAnyPublisher(),
            profiles: browserManager.profileManager.$profiles.eraseToAnyPublisher(),
            profileRuntimeChanged: Publishers.Merge(
                browserManager.$currentProfile.map { _ in () },
                browserManager.$isTransitioningProfile.map { _ in () }
            )
            .eraseToAnyPublisher(),
            liveFoldersChanged: Publishers.Merge(
                browserManager.liveFolderManager.$sourcesByFolderId.map { _ in () },
                browserManager.liveFolderManager.$itemsBySourceId.map { _ in () }
            )
            .eraseToAnyPublisher()
        )

        return WindowViewBrowserContext(
            splitUpdates: browserManager.splitComposition.updates,
            splitQuery: browserManager.splitComposition.query,
            splitPreviews: browserManager.splitComposition.previews,
            splitLayout: browserManager.splitComposition.layout,
            splitDrops: browserManager.splitComposition.drops,
            splitDropTargets: browserManager.splitComposition.dropTargets,
            webViewOwnershipQuery: browserManager.webViewRuntime.ownershipQuery,
            trackedWebViewAdmission: browserManager.webViewRuntime
                .trackedWebViewAdmission,
            webViewCompositorRuntime: browserManager.webViewRuntime.compositorRuntime,
            webViewProtectionRuntime: browserManager.webViewRuntime.protectionRuntime,
            findManager: browserManager.findManager,
            floatingBarBrowserContext: browserManager.urlBarBundle
                .floatingBar.browserContext.context,
            sidebarBrowserContext: SidebarBrowserContext.live(
                browserManager: browserManager,
                spaceLifecycle: spaceLifecycle
            ),
            sidebarInventory: inventory,
            sidebarSelection: selection,
            sidebarPinProjection: pinProjection,
            sidebarPinCommands: pinCommands,
            sidebarSpaceLifecycle: spaceLifecycle,
            sidebarRegularTabs: SidebarRegularTabsController.live(
                tabManager: tabManager,
                liveFolderManager: browserManager.liveFolderManager
            ),
            sidebarDragTransactions: dragTransactions,
            sidebarUpdates: updateStreams,
            sidebarHostActions: sidebarHostActions(browserManager: browserManager),
            sidebarHostRecoveryCoordinator: browserManager.sidebarHostRecoveryCoordinator,
            nativeModalPresentation: { [weak browserManager] in
                browserManager?.nativeModalPresentation
            },
            browsingDataDialogContext: browsingDataDialogContext(browserManager: browserManager),
            hasCurrentSpace: { [weak browserManager] in
                browserManager?.tabManager.spaceStateOwner.currentSpace != nil
            },
            showGradientEditor: { [weak browserManager] source in
                browserManager?.chromeBundle.workspaceThemeEditorOwner.showGradientEditor(source: source)
            },
            currentProfileID: { [weak browserManager] in
                browserManager?.currentProfile?.id
            },
            essentialPins: { [weak browserManager] profileId in
                browserManager?.tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId) ?? []
            },
            attachHoverSidebarManager: { [weak browserManager] hoverSidebarManager, windowState in
                guard let browserManager else { return }
                hoverSidebarManager.attach(
                    runtime: BrowserHoverSidebarRuntimeFactory.runtime(for: browserManager),
                    windowState: windowState
                )
            },
            websiteViewBrowserContext: { [browserManager] in
                WebsiteViewContextFactory.websiteViewBrowserContext(
                    for: browserManager
                )
            },
            websiteNativeSurfaceRootBuilders: { [browserManager] in
                WebsiteViewContextFactory.nativeSurfaceRootBuilders(
                    for: browserManager,
                    updaterService: updaterService,
                    defaultBrowserService: defaultBrowserService
                )
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            workspaceTheme: { [weak browserManager] spaceId in
                guard let spaceId else { return nil }
                return browserManager?.tabManager.spaceStateOwner.space(with: spaceId)?
                    .workspaceTheme
            },
            isNativeModalPresented: { [weak browserManager] windowId in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.isNativeModalPresented(in: windowId) ?? false
            },
            nativeModalPresentationBindingDismissed: { [weak browserManager] windowId in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.nativeModalPresentationBindingDismissed(for: windowId)
            },
            dismissNativeModalPresentation: { [weak browserManager] in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.dismissNativeModalPresentation()
            },
            findCurrentTabId: { [weak browserManager] in
                browserManager?.findManager.currentTab?.id
            }
        )
    }

    private static func sidebarHostActions(browserManager: BrowserManager) -> SidebarHostActions {
        SidebarHostActions(
            updateSidebarWidth: { [weak browserManager] width, windowState, persist in
                browserManager?.chromeBundle.sidebarPresentationOwner.updateSidebarWidth(width, for: windowState, persist: persist)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            },
            dismissThemePickerCommittingIfNeeded: { [weak browserManager] in
                browserManager?.chromeBundle.workspaceThemeEditorOwner.dismissThemePickerCommittingIfNeeded()
            }
        )
    }

    private static func browsingDataDialogContext(
        browserManager: BrowserManager
    ) -> () -> SumiBrowsingDataDialogContext {
        { [browserManager, cleanupService = browserManager.browsingDataCleanupService] in
            SumiBrowsingDataDialogContext(
                cleanupService: cleanupService,
                profileSnapshot: { [weak browserManager] in
                    browserManager?.profileManager.profiles ?? []
                },
                activeCleanupDependencies: {
                    activeCleanupDependencies(browserManager: browserManager)
                },
                dismissNativeModalPresentation: { [weak browserManager] in
                    browserManager?.chromeBundle.nativeDialogPresentationOwner.dismissNativeModalPresentation()
                }
            )
        }
    }

    private static func activeCleanupDependencies(
        browserManager: BrowserManager?
    ) -> BrowsingDataDialogCleanupDependencies? {
        guard let browserManager,
              browserManager.currentProfile != nil
        else {
            return nil
        }
        return BrowsingDataDialogCleanupDependencies(
            historyManager: browserManager.historyManager,
            profiles: browserManager.profileManager.profiles,
            websiteDataCleanupService: browserManager.dataServices.websiteDataCleanupService
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
