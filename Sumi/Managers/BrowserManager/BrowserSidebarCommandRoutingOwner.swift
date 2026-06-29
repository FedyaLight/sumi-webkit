import Foundation

@MainActor
final class BrowserSidebarCommandRoutingOwner {
    struct Dependencies {
        let canCreateFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Bool
        let showGradientEditor: @MainActor (SidebarTransientPresentationSource) -> Void
        let toggleSidebar: @MainActor (BrowserWindowState) -> Void
        let openAppearanceSettings: @MainActor (BrowserWindowState) -> Void
        let closeDownloadsPopover: @MainActor (BrowserWindowState) -> Void
        let requestUserTabActivation: @MainActor (Tab, BrowserWindowState) -> Void
        let closeTab: @MainActor (Tab, BrowserWindowState) -> Void
        let moveTabUp: @MainActor (UUID) -> Void
        let moveTabDown: @MainActor (UUID) -> Void
        let focusSplitGroup: @MainActor (SplitGroup, BrowserWindowState) -> Void
        let restoreShortcutSplitMember: @MainActor (UUID, SplitGroup, BrowserWindowState) -> Void
        let openForegroundTab: @MainActor (String, BrowserWindowState, UUID?) -> Tab?
        let openNewTabOrFloatingBar: @MainActor (BrowserWindowState) -> Void
        let duplicateTab: @MainActor (Tab, BrowserWindowState) -> Void
        let pinShortcutGlobally: @MainActor (ShortcutPin, BrowserWindowState, UUID, Tab?) -> Void
        let toggleDownloadsPopover: @MainActor (BrowserWindowState) -> Void
        let createFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
        let createRSSLiveFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
        let createGitHubPullRequestsLiveFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
        let createGitHubIssuesLiveFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func makeActions() -> SidebarBrowserCommandActions {
        SidebarBrowserCommandActions(
            canCreateFolderInCurrentSpace: { [weak self] windowState in
                self?.dependencies.canCreateFolderInCurrentSpace(windowState) ?? false
            },
            showGradientEditor: { [weak self] source in
                self?.dependencies.showGradientEditor(source)
            },
            toggleSidebar: { [weak self] windowState in
                self?.dependencies.toggleSidebar(windowState)
            },
            openAppearanceSettings: { [weak self] windowState in
                self?.dependencies.openAppearanceSettings(windowState)
            },
            closeDownloadsPopover: { [weak self] windowState in
                self?.dependencies.closeDownloadsPopover(windowState)
            },
            requestUserTabActivation: { [weak self] tab, windowState in
                self?.dependencies.requestUserTabActivation(tab, windowState)
            },
            closeTab: { [weak self] tab, windowState in
                self?.dependencies.closeTab(tab, windowState)
            },
            moveTabUp: { [weak self] tabId in
                self?.dependencies.moveTabUp(tabId)
            },
            moveTabDown: { [weak self] tabId in
                self?.dependencies.moveTabDown(tabId)
            },
            focusSplitGroup: { [weak self] group, windowState in
                self?.dependencies.focusSplitGroup(group, windowState)
            },
            restoreShortcutSplitMember: { [weak self] memberId, group, windowState in
                self?.dependencies.restoreShortcutSplitMember(memberId, group, windowState)
            },
            openForegroundTab: { [weak self] url, windowState, preferredSpaceId in
                self?.dependencies.openForegroundTab(url, windowState, preferredSpaceId)
            },
            openNewTabOrFloatingBar: { [weak self] windowState in
                self?.dependencies.openNewTabOrFloatingBar(windowState)
            },
            duplicateTab: { [weak self] tab, windowState in
                self?.dependencies.duplicateTab(tab, windowState)
            },
            pinShortcutGlobally: { [weak self] pin, windowState, spaceId, liveTab in
                self?.dependencies.pinShortcutGlobally(pin, windowState, spaceId, liveTab)
            },
            toggleDownloadsPopover: { [weak self] windowState in
                self?.dependencies.toggleDownloadsPopover(windowState)
            },
            createFolderInCurrentSpace: { [weak self] windowState in
                self?.dependencies.createFolderInCurrentSpace(windowState)
            },
            createRSSLiveFolderInCurrentSpace: { [weak self] windowState in
                self?.dependencies.createRSSLiveFolderInCurrentSpace(windowState)
            },
            createGitHubPullRequestsLiveFolderInCurrentSpace: { [weak self] windowState in
                self?.dependencies.createGitHubPullRequestsLiveFolderInCurrentSpace(windowState)
            },
            createGitHubIssuesLiveFolderInCurrentSpace: { [weak self] windowState in
                self?.dependencies.createGitHubIssuesLiveFolderInCurrentSpace(windowState)
            }
        )
    }
}

extension BrowserSidebarCommandRoutingOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            canCreateFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.sidebarFolderCommandOwner.canCreateFolderInCurrentSpace(in: windowState) ?? false
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
                browserManager?.sidebarTabCommandOwner.requestUserTabActivation(tab, in: windowState)
            },
            closeTab: { [weak browserManager] tab, windowState in
                browserManager?.sidebarTabCommandOwner.closeTab(tab, in: windowState)
            },
            moveTabUp: { [weak browserManager] tabId in
                browserManager?.sidebarTabCommandOwner.moveTabUp(tabId)
            },
            moveTabDown: { [weak browserManager] tabId in
                browserManager?.sidebarTabCommandOwner.moveTabDown(tabId)
            },
            focusSplitGroup: { [weak browserManager] group, windowState in
                browserManager?.sidebarSplitShortcutRoutingOwner.focusSplitGroup(group, in: windowState)
            },
            restoreShortcutSplitMember: { [weak browserManager] memberId, group, windowState in
                browserManager?.sidebarSplitShortcutRoutingOwner.restoreShortcutSplitMember(
                    memberId,
                    from: group,
                    in: windowState
                )
            },
            openForegroundTab: { [weak browserManager] url, windowState, preferredSpaceId in
                browserManager?.sidebarTabCommandOwner.openForegroundTab(
                    url,
                    in: windowState,
                    preferredSpaceId: preferredSpaceId
                )
            },
            openNewTabOrFloatingBar: { [weak browserManager] windowState in
                browserManager?.sidebarTabCommandOwner.openNewTabOrFloatingBar(in: windowState)
            },
            duplicateTab: { [weak browserManager] tab, windowState in
                browserManager?.sidebarTabCommandOwner.duplicateTab(tab, in: windowState)
            },
            pinShortcutGlobally: { [weak browserManager] pin, windowState, spaceId, liveTab in
                browserManager?.sidebarShortcutPromotionOwner.pinShortcutGlobally(
                    pin,
                    in: windowState,
                    spaceId: spaceId,
                    liveTab: liveTab
                )
            },
            toggleDownloadsPopover: { [weak browserManager] windowState in
                browserManager?.toggleDownloadsPopover(in: windowState)
            },
            createFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.sidebarFolderCommandOwner.createFolderInCurrentSpace(in: windowState)
            },
            createRSSLiveFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.sidebarFolderCommandOwner.createRSSLiveFolderInCurrentSpace(in: windowState)
            },
            createGitHubPullRequestsLiveFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.sidebarFolderCommandOwner.createGitHubPullRequestsLiveFolderInCurrentSpace(
                    in: windowState
                )
            },
            createGitHubIssuesLiveFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.sidebarFolderCommandOwner.createGitHubIssuesLiveFolderInCurrentSpace(
                    in: windowState
                )
            }
        )
    }
}
