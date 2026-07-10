import Foundation

@MainActor
struct WindowSessionSpaceResolver {
    let tabManager: TabManager

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
        return tabManager.spaceStateOwner.spaces.first { $0.id == spaceId }
    }

    private func currentTabSpaceId(
        for windowState: BrowserWindowState
    ) -> UUID? {
        guard let currentTabId = windowState.currentTabId,
              let spaceId = tabManager.tabCollectionMembershipOwner
                .tab(for: currentTabId)?.spaceId,
              containsSpace(spaceId) else {
            return nil
        }
        return spaceId
    }

    private func firstSpaceId(for profileId: UUID) -> UUID? {
        tabManager.spaceStateOwner.spaces
            .first(where: { $0.profileId == profileId })?.id
    }

    private func containsSpace(_ spaceId: UUID) -> Bool {
        tabManager.spaceStateOwner.spaces.contains { $0.id == spaceId }
    }
}
