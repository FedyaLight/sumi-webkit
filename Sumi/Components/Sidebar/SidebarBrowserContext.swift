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
struct SidebarBrowserContext {
    let tabManager: TabManager
    let profileManager: ProfileManager
    let liveFolderManager: SumiLiveFolderManager
    let splitManager: SplitViewManager
    let downloadManager: DownloadManager
    let downloadsPopoverPresenter: DownloadsPopoverPresenter
    let glanceManager: GlanceManager
    let extensionSurfaceStore: BrowserExtensionSurfaceStore
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
    let completePendingSplitGroupFocusIfReady: (BrowserWindowState, UUID) -> Void
    let setActiveSpace: (Space, BrowserWindowState) -> Void
    let setActiveSpaceFromTransition: (Space, BrowserWindowState, SpaceTransitionIdentity) -> Void
    let beginInteractiveSpaceTransition: (Space, Space, SpaceTransitionIdentity, BrowserWindowState) -> SpaceTransitionIdentity?
    let updateInteractiveSpaceTransition: (Double, SpaceTransitionIdentity?, BrowserWindowState) -> Void
    let cancelInteractiveSpaceTransition: (SpaceTransitionIdentity?, BrowserWindowState) -> Void
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
    let createGitHubPullRequestsLiveFolderInCurrentSpace: (BrowserWindowState) -> Void
    let createGitHubIssuesLiveFolderInCurrentSpace: (BrowserWindowState) -> Void

    static func live(browserManager: BrowserManager) -> SidebarBrowserContext {
        SidebarBrowserContext(
            tabManager: browserManager.tabManager,
            profileManager: browserManager.profileManager,
            liveFolderManager: browserManager.liveFolderManager,
            splitManager: browserManager.splitManager,
            downloadManager: browserManager.downloadManager,
            downloadsPopoverPresenter: browserManager.downloadsPopoverPresenter,
            glanceManager: browserManager.glanceManager,
            extensionSurfaceStore: browserManager.extensionsModule.surfaceStore,
            presentationActions: SidebarBrowserPresentationActions(
                showShortcutEditor: { [weak browserManager] pin, windowState, themeContext, source in
                    browserManager?.sidebarEditorPresentationOwner.showShortcutEditor(
                        for: pin,
                        in: windowState,
                        themeContext: themeContext,
                        source: source
                    )
                },
                showFolderEditor: { [weak browserManager] folder, windowState, themeContext, source in
                    browserManager?.sidebarEditorPresentationOwner.showFolderEditor(
                        for: folder,
                        in: windowState,
                        themeContext: themeContext,
                        source: source
                    )
                },
                showSpaceEditor: { [weak browserManager] space, windowState, themeContext, source in
                    browserManager?.sidebarEditorPresentationOwner.showSpaceEditor(
                        for: space,
                        in: windowState,
                        themeContext: themeContext,
                        source: source
                    )
                },
                showGradientEditorForSpace: { [weak browserManager] space, source in
                    browserManager?.showGradientEditor(for: space, source: source)
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
                    browserManager?.presentSharingServicePicker(items, source: source)
                }
            ),
            headerContext: { windowState in
                browserManager.sidebarHeaderBrowserContext(for: windowState)
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
                mediaStore.configure(browserManager: browserManager, windowState: windowState)
            },
            completePendingSplitGroupFocusIfReady: { [weak browserManager] windowState, spaceId in
                browserManager?.completePendingSplitGroupFocusIfReady(
                    in: windowState,
                    spaceId: spaceId
                )
            },
            setActiveSpace: { [weak browserManager] space, windowState in
                browserManager?.setActiveSpace(space, in: windowState)
            },
            setActiveSpaceFromTransition: { [weak browserManager] space, windowState, identity in
                browserManager?.setActiveSpace(
                    space,
                    in: windowState,
                    completingTransition: identity
                )
            },
            beginInteractiveSpaceTransition: { [weak browserManager] source, destination, identity, windowState in
                browserManager?.beginInteractiveSpaceTransition(
                    from: source,
                    to: destination,
                    identity: identity,
                    in: windowState
                )
            },
            updateInteractiveSpaceTransition: { [weak browserManager] progress, identity, windowState in
                browserManager?.updateInteractiveSpaceTransition(
                    progress: progress,
                    identity: identity,
                    in: windowState
                )
            },
            cancelInteractiveSpaceTransition: { [weak browserManager] identity, windowState in
                browserManager?.cancelInteractiveSpaceTransition(identity: identity, in: windowState)
            },
            canCreateFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.spaceForSidebarActions(in: windowState) != nil
            },
            showGradientEditor: { [weak browserManager] source in
                browserManager?.showGradientEditor(source: source)
            },
            toggleSidebar: { [weak browserManager] windowState in
                browserManager?.toggleSidebar(for: windowState)
            },
            openAppearanceSettings: { [weak browserManager] windowState in
                browserManager?.openSettingsTab(selecting: .appearance, in: windowState)
            },
            closeDownloadsPopover: { [weak browserManager] windowState in
                browserManager?.closeDownloadsPopover(in: windowState)
            },
            requestUserTabActivation: { [weak browserManager] tab, windowState in
                browserManager?.requestUserTabActivation(tab, in: windowState)
            },
            closeTab: { [weak browserManager] tab, windowState in
                browserManager?.closeTab(tab, in: windowState)
            },
            moveTabUp: { [weak browserManager] tabId in
                browserManager?.tabManager.moveTabUp(tabId)
            },
            moveTabDown: { [weak browserManager] tabId in
                browserManager?.tabManager.moveTabDown(tabId)
            },
            focusSplitGroup: { [weak browserManager] group, windowState in
                browserManager?.focusSplitGroup(group, in: windowState)
            },
            restoreShortcutSplitMember: { [weak browserManager] memberId, group, windowState in
                browserManager?.restoreShortcutSplitMember(memberId, from: group, in: windowState)
            },
            openForegroundTab: { [weak browserManager] url, windowState, preferredSpaceId in
                browserManager?.openNewTab(
                    url: url,
                    context: .foreground(
                        windowState: windowState,
                        preferredSpaceId: preferredSpaceId
                    )
                )
            },
            openNewTabOrFloatingBar: { [weak browserManager] windowState in
                browserManager?.openNewTabOrFloatingBar(in: windowState)
            },
            duplicateTab: { [weak browserManager] tab, windowState in
                browserManager?.duplicateTab(tab, in: windowState)
            },
            pinShortcutGlobally: { [weak browserManager] pin, windowState, spaceId, liveTab in
                guard let browserManager else { return }
                let syntheticTab = Tab(
                    url: pin.launchURL,
                    name: pin.resolvedDisplayTitle(liveTab: liveTab),
                    favicon: SumiPersistentGlyph.launcherSystemImageFallback,
                    spaceId: spaceId,
                    index: 0,
                    browserManager: browserManager
                )
                browserManager.tabManager.pinTab(
                    syntheticTab,
                    context: .init(windowState: windowState, spaceId: spaceId)
                )
            },
            toggleDownloadsPopover: { [weak browserManager] windowState in
                browserManager?.toggleDownloadsPopover(in: windowState)
            },
            createFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.createFolderInCurrentSpace(in: windowState)
            },
            createRSSLiveFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.createRSSLiveFolderInCurrentSpace(in: windowState)
            },
            createGitHubPullRequestsLiveFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.createGitHubPullRequestsLiveFolderInCurrentSpace(in: windowState)
            },
            createGitHubIssuesLiveFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.createGitHubIssuesLiveFolderInCurrentSpace(in: windowState)
            }
        )
    }
}
