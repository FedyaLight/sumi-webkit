import Foundation
import SumiDomain

/// Keeps one window's Space/Profile identity coherent without process-global
/// fallbacks.
@MainActor
final class BrowserWindowSpaceContextReconciler {
    private let membership: TabCollectionMembershipOwner
    private let spaces: TabSpaceCollectionStateOwner

    init(
        membership: TabCollectionMembershipOwner,
        spaces: TabSpaceCollectionStateOwner
    ) {
        self.membership = membership
        self.spaces = spaces
    }

    @discardableResult
    func reconcile(_ windowState: BrowserWindowState) -> Bool {
        guard !windowState.isIncognito,
              !windowState.restorationState.isAwaitingInitialResolution
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

        return didChange
    }

    func synchronize(_ windowState: BrowserWindowState) {
        guard !windowState.isIncognito,
              !windowState.restorationState.isAwaitingInitialResolution
        else {
            return
        }

        let currentSpace = space(for: windowState.currentSpaceId)
        if windowState.currentProfileId != currentSpace?.profileId {
            windowState.currentProfileId = currentSpace?.profileId
        }
    }

    func workspaceTheme(for windowState: BrowserWindowState) -> WorkspaceTheme {
        space(for: windowState.currentSpaceId)?.workspaceTheme ?? .default
    }

    private func resolvedSpace(for windowState: BrowserWindowState) -> Space? {
        if let currentSpace = space(for: windowState.currentSpaceId) {
            return currentSpace
        }

        if let currentTabId = windowState.currentTabId,
           let tabSpaceId = membership.tab(for: currentTabId)?.spaceId,
           let tabSpace = space(for: tabSpaceId) {
            return tabSpace
        }

        if let profileId = windowState.currentProfileId {
            return spaces.spaces.first {
                $0.profileId == profileId
            }
        }

        return nil
    }

    private func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return spaces.space(with: spaceId)
    }
}
