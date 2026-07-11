import Foundation

/// Keeps one window's Space/Profile identity coherent without process-global
/// fallbacks.
@MainActor
final class BrowserWindowSpaceContextReconciler {
    private let tabManager: TabManager
    private let commitWorkspaceTheme: (WorkspaceTheme, BrowserWindowState) -> Void

    init(
        tabManager: TabManager,
        commitWorkspaceTheme: @escaping (WorkspaceTheme, BrowserWindowState) -> Void
    ) {
        self.tabManager = tabManager
        self.commitWorkspaceTheme = commitWorkspaceTheme
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            tabManager: browserManager.tabManager,
            commitWorkspaceTheme: { [weak browserManager] theme, windowState in
                browserManager?.chromeBundle.workspaceThemeTransitionOwner
                    .commitWorkspaceTheme(theme, for: windowState)
            }
        )
    }

    @discardableResult
    func reconcile(_ windowState: BrowserWindowState) -> Bool {
        guard !windowState.isIncognito,
              !windowState.isAwaitingInitialSessionResolution
        else {
            return false
        }

        let resolvedSpace = resolvedSpace(for: windowState)
        var didChange = false

        if windowState.currentSpaceId != resolvedSpace?.id {
            windowState.currentSpaceId = resolvedSpace?.id
            didChange = true
        }

        let profileId = resolvedSpace?.profileId
        if windowState.currentProfileId != profileId {
            windowState.currentProfileId = profileId
            didChange = true
        }

        commitWorkspaceTheme(resolvedSpace?.workspaceTheme ?? .default, windowState)
        return didChange
    }

    func synchronize(_ windowState: BrowserWindowState) {
        guard !windowState.isIncognito,
              !windowState.isAwaitingInitialSessionResolution
        else {
            return
        }

        let currentSpace = space(for: windowState.currentSpaceId)
        if windowState.currentProfileId != currentSpace?.profileId {
            windowState.currentProfileId = currentSpace?.profileId
        }
    }

    private func resolvedSpace(for windowState: BrowserWindowState) -> Space? {
        if let currentSpace = space(for: windowState.currentSpaceId) {
            return currentSpace
        }

        if let currentTabId = windowState.currentTabId,
           let tabSpaceId = tabManager.tabCollectionMembershipOwner
               .tab(for: currentTabId)?.spaceId,
           let tabSpace = space(for: tabSpaceId) {
            return tabSpace
        }

        if let profileId = windowState.currentProfileId {
            return tabManager.spaceStateOwner.spaces.first {
                $0.profileId == profileId
            }
        }

        return nil
    }

    private func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return tabManager.spaceStateOwner.space(with: spaceId)
    }
}
