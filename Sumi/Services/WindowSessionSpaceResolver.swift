import Foundation

@MainActor
struct WindowSessionSpaceResolver {
    let spaces: TabSpaceCollectionStateOwner
    let membership: TabCollectionMembershipOwner

    func resolve(
        for windowState: BrowserWindowState,
        seededProfileId: UUID? = nil
    ) -> UUID? {
        if let windowSpaceId = windowState.currentSpaceId,
           containsSpace(windowSpaceId) {
            return windowSpaceId
        }

        if let tabSpaceId = currentTabSpaceId(for: windowState) {
            return tabSpaceId
        }

        if let profileId = windowState.currentProfileId,
           let profileSpaceId = firstSpaceId(for: profileId) {
            return profileSpaceId
        }
        windowState.currentProfileId = nil

        if let seededProfileId,
           let profileSpaceId = firstSpaceId(for: seededProfileId) {
            return profileSpaceId
        }

        return nil
    }

    func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return spaces.space(with: spaceId)
    }

    private func currentTabSpaceId(
        for windowState: BrowserWindowState
    ) -> UUID? {
        guard let currentTabId = windowState.currentTabId,
              let spaceId = membership.tab(for: currentTabId)?.spaceId,
              containsSpace(spaceId) else {
            return nil
        }
        return spaceId
    }

    private func firstSpaceId(for profileId: UUID) -> UUID? {
        spaces.firstSpace(forProfile: profileId)?.id
    }

    private func containsSpace(_ spaceId: UUID) -> Bool {
        spaces.contains(spaceId: spaceId)
    }
}
