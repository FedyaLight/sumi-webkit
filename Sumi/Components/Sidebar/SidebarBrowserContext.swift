import AppKit
import SumiDomain
import SwiftUI

@MainActor
struct SidebarBrowserPresentationActions {
    let showShortcutEditor: (ShortcutPin, BrowserWindowState, ResolvedThemeContext, SidebarTransientPresentationSource) -> Void
    let showFolderEditor: (TabFolder, BrowserWindowState, ResolvedThemeContext, SidebarTransientPresentationSource) -> Void
    let showFolderSearchPopover: (FolderSearchPopoverRequest, BrowserWindowState, ResolvedThemeContext, SidebarTransientPresentationSource) -> Void
    let folderSearchAnchorHoverChanged: (UUID, BrowserWindowState, Bool) -> Void
    let showSpaceEditor: (Space, BrowserWindowState, ResolvedThemeContext, SidebarTransientPresentationSource) -> Void
    let showGradientEditorForSpace: (Space, SidebarTransientPresentationSource) -> Void
    let confirmDeleteSpace: (Space, BrowserWindowState) -> Void
    let presentSharingServicePicker: ([Any], SidebarTransientPresentationSource) -> Void
}

@MainActor
struct SidebarSpaceTransitionActions {
    let completePendingSplitGroupFocusIfReady: (BrowserWindowState, UUID) -> Void
    let setActiveSpace: (Space, BrowserWindowState) -> Void
    let setActiveSpaceFromTransition: (Space, BrowserWindowState, SpaceTransitionIdentity) -> Void
    let beginInteractiveSpaceTransition: (Space, Space, SpaceTransitionIdentity, BrowserWindowState) -> SpaceTransitionIdentity?
    let updateInteractiveSpaceTransition: (Double, SpaceTransitionIdentity?, BrowserWindowState) -> Void
    let cancelInteractiveSpaceTransition: (SpaceTransitionIdentity?, BrowserWindowState) -> Void
}

@MainActor
struct SidebarBrowserCommandActions {
    let canCreateFolderInCurrentSpace: (BrowserWindowState) -> Bool
    let showGradientEditor: (SidebarTransientPresentationSource) -> Void
    let toggleSidebar: (BrowserWindowState) -> Void
    let openAppearanceSettings: (BrowserWindowState) -> Void
    let closeDownloadsPopover: (BrowserWindowState) -> Void
    let requestUserTabActivation: (Tab, BrowserWindowState) -> Void
    let closeTab: (Tab, BrowserWindowState) -> Void
    let moveTabUp: (UUID) -> Void
    let moveTabDown: (UUID) -> Void
    let focusSplitGroup: (UUID, SplitMemberID?, UUID) -> Void
    let restoreShortcutSplitMember: (UUID, SplitMemberID, UUID) -> Void
    let closeSplitMember: (UUID, SplitMemberID, UUID) -> Void
    let openForegroundTab: (String, BrowserWindowState, UUID?) -> Tab?
    let openNewTabOrFloatingBar: (BrowserWindowState) -> Void
    let duplicateTab: (Tab, BrowserWindowState) -> Void
    let pinShortcutGlobally: (ShortcutPin, BrowserWindowState, UUID, Tab?) -> Void
    let toggleDownloadsPopover: (BrowserWindowState) -> Void
    let createFolderInCurrentSpace: (BrowserWindowState) -> Void
    let createRSSLiveFolderInCurrentSpace: (BrowserWindowState) -> Void
    let createGitHubPRFolderInCurrentSpace: (BrowserWindowState) -> Void
    let createGitHubIssuesFolderInCurrentSpace: (BrowserWindowState) -> Void
    let unloadShortcutPin: (ShortcutPin, BrowserWindowState) -> Void
    let unloadShortcutPins: ([ShortcutPin], BrowserWindowState) -> Void
}

@MainActor
struct SidebarBrowserContext {
    let tabManager: TabManager
    let profileManager: ProfileManager
    let liveFolderManager: SumiLiveFolderManager
    let splitQuery: WindowSplitQuery
    let splitLayout: SplitLayoutService
    let emptySplitCreation: EmptySplitCreationWorkflow
    let downloadManager: DownloadManager
    let downloadsPopoverPresenter: DownloadsPopoverPresenter
    let glanceManager: GlanceManager
    let extensionSurfaceStore: BrowserExtensionSurfaceStore
    let regularTabs: any SidebarRegularTabsControlling
    let presentationActions: SidebarBrowserPresentationActions
    let headerContext: (BrowserWindowState) -> SidebarHeaderBrowserContext
    let tabStructuralRevision: () -> UInt
    let isTransitioningProfile: () -> Bool
    let currentProfile: () -> Profile?
    let currentTab: (BrowserWindowState) -> Tab?
    let extensionToolbarSlots: ([InstalledExtension], UUID?) -> [PinnedToolbarSlot]
    let extensionActionBrowserContext: (BrowserWindowState) -> ExtensionActionBrowserContext
    let savedSidebarWidth: (BrowserWindowState) -> CGFloat
    let performDrop: (NSPasteboard, SidebarDropResolution, BrowserWindowState?) -> Bool
    let configureMediaStore: (SumiBackgroundMediaCardStore, BrowserWindowState) -> Void
    let spaceTransitions: SidebarSpaceTransitionActions
    let commands: SidebarBrowserCommandActions
    let windowRegistry: () -> WindowRegistry?

    static func live(browserManager: BrowserManager) -> SidebarBrowserContext {
        let tabManager = browserManager.tabManager
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
        let urlDropService = SidebarURLDropService(
            tabOpening: browserManager.tabLifecycleService.opening,
            nativeSurfaces: browserManager.chromeBundle.nativeSurfaceRoutingOwner,
            destinations: SidebarURLDropDestinationCatalog(
                spaces: tabManager.spaceStateOwner,
                folders: tabManager.folderCollectionStateOwner,
                essentials: tabManager.essentialsShortcutPlacementOwner
            ),
            shortcutInsertion: shortcutInsertion
        )
        let dragSourceInventory = SidebarDragSourceInventory(
            essentialPins: tabManager.shortcutPinCollectionStateOwner,
            splitOrdering: tabManager.splitGroupSidebarOrdering,
            regularTabs: tabManager.regularTabCollectionOwner,
            folders: tabManager.folderCollectionStateOwner,
            spacePinned: tabManager.spacePinnedStructureOwner
        )
        let dragOperations = tabManager.sidebarDragRouter
        return SidebarBrowserContext(
            tabManager: browserManager.tabManager,
            profileManager: browserManager.profileManager,
            liveFolderManager: browserManager.liveFolderManager,
            splitQuery: browserManager.splitComposition.query,
            splitLayout: browserManager.splitComposition.layout,
            emptySplitCreation: browserManager.splitComposition.emptyCreation,
            downloadManager: browserManager.downloadManager,
            downloadsPopoverPresenter: browserManager.chromeBundle.commands.downloadsPopoverPresenter,
            glanceManager: browserManager.glanceManager,
            extensionSurfaceStore: browserManager.optionalModules.extensions.surfaceStore,
            regularTabs: SidebarRegularTabsController.live(
                tabManager: browserManager.tabManager,
                liveFolderManager: browserManager.liveFolderManager
            ),
            presentationActions: SidebarBrowserPresentationActions(
                showShortcutEditor: { [weak browserManager] pin, windowState, themeContext, source in
                    browserManager?.sidebarCommandService.editorPresentation.showShortcutEditor(
                        for: pin,
                        in: windowState,
                        themeContext: themeContext,
                        source: source
                    )
                },
                showFolderEditor: { [weak browserManager] folder, windowState, themeContext, source in
                    browserManager?.sidebarCommandService.editorPresentation.showFolderEditor(
                        for: folder,
                        in: windowState,
                        themeContext: themeContext,
                        source: source
                    )
                },
                showFolderSearchPopover: { [weak browserManager] request, windowState, themeContext, source in
                    browserManager?.sidebarCommandService.editorPresentation.showFolderSearchPopover(
                        request: request,
                        in: windowState,
                        themeContext: themeContext,
                        source: source
                    )
                },
                folderSearchAnchorHoverChanged: { [weak browserManager] folderID, windowState, hovering in
                    browserManager?.sidebarCommandService.editorPresentation.setFolderSearchAnchorHovered(
                        folderID: folderID,
                        in: windowState,
                        hovering: hovering
                    )
                },
                showSpaceEditor: { [weak browserManager] space, windowState, themeContext, source in
                    browserManager?.sidebarCommandService.editorPresentation.showSpaceEditor(
                        for: space,
                        in: windowState,
                        themeContext: themeContext,
                        source: source
                    )
                },
                showGradientEditorForSpace: { [weak browserManager] space, source in
                    browserManager?.chromeBundle.workspaceThemeEditorOwner.showGradientEditor(for: space, source: source)
                },
                confirmDeleteSpace: { [weak browserManager] space, windowState in
                    guard let browserManager else { return }
                    SpaceDeletionConfirmationPresenter.confirmDelete(
                        space: space,
                        browserManager: browserManager,
                        window: windowState.shellWindow(in: browserManager.windowRegistry)
                    )
                },
                presentSharingServicePicker: { [weak browserManager] items, source in
                    browserManager?.chromeBundle.nativeDialogPresentationOwner.presentSharingServicePicker(items, source: source)
                }
            ),
            headerContext: { windowState in
                browserManager.urlBarBundle.contextOwner.sidebarHeaderContext(for: windowState)
            },
            tabStructuralRevision: { [weak browserManager] in
                browserManager?.tabStructuralRevision ?? 0
            },
            isTransitioningProfile: { [weak browserManager] in
                browserManager?.isTransitioningProfile ?? false
            },
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            extensionToolbarSlots: { [weak browserManager] enabledExtensions, profileId in
                guard let browserManager else { return [] }
                return browserManager.optionalModules.extensions.orderedPinnedToolbarSlots(
                    enabledExtensions: enabledExtensions,
                    sumiScriptsManagerEnabled: browserManager.optionalModules.userscripts.isEnabled,
                    profileId: profileId
                )
            },
            extensionActionBrowserContext: { windowState in
                ExtensionActionBrowserContext.live(
                    browserManager: browserManager,
                    windowState: windowState
                )
            },
            savedSidebarWidth: { [weak browserManager] windowState in
                browserManager?.chromeBundle.sidebarPresentationOwner.savedSidebarWidth(for: windowState) ?? BrowserWindowState.sidebarDefaultWidth
            },
            performDrop: { [weak dragOperations, urlDropService, dragSourceInventory] pasteboard, resolution, windowState in
                guard let dragOperations else { return false }
                return SidebarDropCoordinator.performDrop(
                    pasteboard: pasteboard,
                    resolution: resolution,
                    sourceInventory: dragSourceInventory,
                    dragOperations: dragOperations,
                    urlDropService: urlDropService,
                    windowState: windowState
                )
            },
            configureMediaStore: { [weak browserManager] mediaStore, windowState in
                guard let browserManager else { return }
                mediaStore.configure(
                    context: BrowserManagerRuntimeWiring.nativeNowPlayingRuntimeContext(
                        for: browserManager
                    ),
                    windowState: windowState
                )
            },
            spaceTransitions: browserManager.sidebarCommandService.makeSpaceTransitionActions(),
            commands: browserManager.sidebarCommandService.makeCommandActions(),
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            }
        )
    }
}
