import Foundation

enum DeletedProfileTabAssignment: Equatable {
    case none
    case assign(UUID?)
}

/// Centralizes effective-profile resolution. It reads model/runtime state but
/// never mutates Tabs, Spaces, WebViews, or persistence.
@MainActor
final class ProfileAssignmentPolicy {
    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func profileExists(_ profileID: UUID) -> Bool {
        tabManager.runtimePorts?.profileExists(profileID) ?? true
    }

    func profile(with profileID: UUID) -> Profile? {
        tabManager.runtimePorts?.profile(with: profileID)
    }

    func resolvedAssignmentProfile(
        for tab: Tab,
        desiredProfileID: UUID?
    ) -> Profile? {
        guard let runtime = tabManager.runtimePorts else { return nil }
        if let desiredProfileID {
            return runtime.profile(with: desiredProfileID)
        }
        if let spaceID = tab.spaceId,
           let inheritedProfileID = tabManager.spaceStateOwner.profileId(
               for: spaceID
           ), let profile = runtime.profile(with: inheritedProfileID) {
            return profile
        }
        if let currentProfileID = runtime.currentProfileId,
           let profile = runtime.profile(with: currentProfileID) {
            return profile
        }
        if let defaultProfileID = runtime.defaultProfileId {
            return runtime.profile(with: defaultProfileID)
        }
        return nil
    }

    func resolvedPlacementProfile(profileID: UUID) -> Profile? {
        tabManager.runtimePorts?.profile(with: profileID)
    }

    func liveDocumentURL(for tab: Tab) -> URL? {
        tabManager.runtimePorts?.webViewLifecycle.anyLiveWebView(for: tab)?.url
    }

    func profileIDsForSpaceTransition(
        tab: Tab,
        targetSpaceID: UUID?,
        desiredProfileID: UUID?
    ) -> (current: UUID, target: UUID)? {
        guard tab.spaceId != targetSpaceID,
              tab.profileId == nil,
              let current = tab.spaceId.flatMap(
                  tabManager.spaceStateOwner.profileId(for:)
              ) ?? tabManager.runtimePorts?.currentProfileId
                  ?? tabManager.runtimePorts?.defaultProfileId,
              let target = desiredProfileID
                  ?? targetSpaceID.flatMap(
                      tabManager.spaceStateOwner.profileId(for:)
                  )
                  ?? tabManager.runtimePorts?.currentProfileId
                  ?? tabManager.runtimePorts?.defaultProfileId,
              current != target else {
            return nil
        }
        return (current, target)
    }

    func deletionAssignment(
        for tab: Tab,
        deletedProfileID: UUID,
        fallbackProfileID: UUID
    ) -> DeletedProfileTabAssignment {
        if tab.profileId == deletedProfileID {
            if let spaceID = tab.spaceId,
               let inheritedProfileID = tabManager.spaceStateOwner.profileId(
                   for: spaceID
               ), inheritedProfileID != deletedProfileID {
                return .assign(nil)
            }
            return .assign(fallbackProfileID)
        }

        let isContextlessDeletedProfile = tab.profileId == nil
            && tab.spaceId == nil
            && resolvedAssignmentProfile(for: tab, desiredProfileID: nil)?.id
                == deletedProfileID
        return isContextlessDeletedProfile
            ? .assign(fallbackProfileID)
            : .none
    }

    func allProfileManagedTabs() -> [Tab] {
        var seen: Set<UUID> = []
        return (
            tabManager.tabCollectionMembershipOwner.allTabs()
                + Array(
                    tabManager.transientTabRegistryOwner
                        .auxiliaryMiniWindowTabsByID.values
                )
        ).filter { seen.insert($0.id).inserted }
    }
}
