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
    let presentationActions: SidebarBrowserPresentationActions
    let tabStructuralRevision: () -> UInt
    let isTransitioningProfile: () -> Bool
    let currentProfile: () -> Profile?
    let currentTab: (BrowserWindowState) -> Tab?
    let space: (UUID?) -> Space?
    let savedSidebarWidth: (BrowserWindowState) -> CGFloat
    let requestUserTabActivation: (Tab, BrowserWindowState) -> Void
    let closeTab: (Tab, BrowserWindowState) -> Void
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
            presentationActions: SidebarBrowserPresentationActions(
                showShortcutEditor: { [weak browserManager] pin, windowState, themeContext, source in
                    browserManager?.showShortcutEditor(
                        for: pin,
                        in: windowState,
                        themeContext: themeContext,
                        source: source
                    )
                },
                showFolderEditor: { [weak browserManager] folder, windowState, themeContext, source in
                    browserManager?.showFolderEditor(
                        for: folder,
                        in: windowState,
                        themeContext: themeContext,
                        source: source
                    )
                },
                showSpaceEditor: { [weak browserManager] space, windowState, themeContext, source in
                    browserManager?.showSpaceEditor(
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
            savedSidebarWidth: { [weak browserManager] windowState in
                browserManager?.getSavedSidebarWidth(for: windowState) ?? BrowserWindowState.sidebarDefaultWidth
            },
            requestUserTabActivation: { [weak browserManager] tab, windowState in
                browserManager?.requestUserTabActivation(tab, in: windowState)
            },
            closeTab: { [weak browserManager] tab, windowState in
                browserManager?.closeTab(tab, in: windowState)
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
