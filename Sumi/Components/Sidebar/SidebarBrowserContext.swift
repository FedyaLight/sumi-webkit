import AppKit
import SwiftUI

@MainActor
struct SidebarBrowserPresentationActions {
    let showShortcutEditor: (ShortcutPin, BrowserWindowState, ResolvedThemeContext, SidebarTransientPresentationSource) -> Void
    let showFolderEditor: (TabFolder, BrowserWindowState, ResolvedThemeContext, SidebarTransientPresentationSource) -> Void
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
    let focusSplitGroup: (SplitGroup, BrowserWindowState) -> Void
    let restoreShortcutSplitMember: (UUID, SplitGroup, BrowserWindowState) -> Void
    let openForegroundTab: (String, BrowserWindowState, UUID?) -> Tab?
    let openNewTabOrFloatingBar: (BrowserWindowState) -> Void
    let duplicateTab: (Tab, BrowserWindowState) -> Void
    let pinShortcutGlobally: (ShortcutPin, BrowserWindowState, UUID, Tab?) -> Void
    let toggleDownloadsPopover: (BrowserWindowState) -> Void
    let createFolderInCurrentSpace: (BrowserWindowState) -> Void
    let createRSSLiveFolderInCurrentSpace: (BrowserWindowState) -> Void
    let createGitHubPRFolderInCurrentSpace: (BrowserWindowState) -> Void
    let createGitHubIssuesFolderInCurrentSpace: (BrowserWindowState) -> Void
}

@MainActor
struct SidebarBrowserContext {
    let tabManager: TabManager
    let profileManager: ProfileManager
    let liveFolderManager: SumiLiveFolderManager
    let splitManager: SplitViewManager
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
    let space: (UUID?) -> Space?
    let extensionToolbarSlots: ([InstalledExtension], UUID?) -> [PinnedToolbarSlot]
    let extensionActionBrowserContext: (BrowserWindowState) -> ExtensionActionBrowserContext
    let savedSidebarWidth: (BrowserWindowState) -> CGFloat
    let performDrop: (NSPasteboard, SidebarDropResolution, BrowserWindowState?) -> Bool
    let configureMediaStore: (SumiBackgroundMediaCardStore, BrowserWindowState) -> Void
    let spaceTransitions: SidebarSpaceTransitionActions
    let commands: SidebarBrowserCommandActions

    static func live(browserManager: BrowserManager) -> SidebarBrowserContext {
        SidebarBrowserContext(
            tabManager: browserManager.tabManager,
            profileManager: browserManager.profileManager,
            liveFolderManager: browserManager.liveFolderManager,
            splitManager: browserManager.splitManager,
            downloadManager: browserManager.downloadManager,
            downloadsPopoverPresenter: browserManager.chromePopoverRoutingOwner.downloadsPopoverPresenter,
            glanceManager: browserManager.glanceManager,
            extensionSurfaceStore: browserManager.extensionsModule.surfaceStore,
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
                showSpaceEditor: { [weak browserManager] space, windowState, themeContext, source in
                    browserManager?.sidebarCommandService.editorPresentation.showSpaceEditor(
                        for: space,
                        in: windowState,
                        themeContext: themeContext,
                        source: source
                    )
                },
                showGradientEditorForSpace: { [weak browserManager] space, source in
                    browserManager?.workspaceThemeEditorOwner.showGradientEditor(for: space, source: source)
                },
                confirmDeleteSpace: { [weak browserManager] space, windowState in
                    guard let browserManager else { return }
                    SpaceDeletionConfirmationPresenter.confirmDelete(
                        space: space,
                        browserManager: browserManager,
                        window: windowState.window
                    )
                },
                presentSharingServicePicker: { [weak browserManager] items, source in
                    browserManager?.nativeDialogPresentationOwner.presentSharingServicePicker(items, source: source)
                }
            ),
            headerContext: { windowState in
                browserManager.urlBarContextOwner.sidebarHeaderContext(for: windowState)
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
                browserManager?.currentTab(for: windowState)
            },
            space: { [weak browserManager] spaceId in
                browserManager?.space(for: spaceId)
            },
            extensionToolbarSlots: { [weak browserManager] enabledExtensions, profileId in
                guard let browserManager else { return [] }
                return browserManager.extensionsModule.orderedPinnedToolbarSlots(
                    enabledExtensions: enabledExtensions,
                    sumiScriptsManagerEnabled: browserManager.userscriptsModule.isEnabled,
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
                browserManager?.getSavedSidebarWidth(for: windowState) ?? BrowserWindowState.sidebarDefaultWidth
            },
            performDrop: { [weak browserManager] pasteboard, resolution, windowState in
                guard let browserManager else { return false }
                return SidebarDropCoordinator.performDrop(
                    pasteboard: pasteboard,
                    resolution: resolution,
                    browserManager: browserManager,
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
            commands: browserManager.sidebarCommandService.makeCommandActions()
        )
    }
}
