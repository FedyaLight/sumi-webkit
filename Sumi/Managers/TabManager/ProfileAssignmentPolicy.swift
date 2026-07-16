import Foundation

enum DeletedProfileTabAssignment: Equatable {
    case none
    case assign(UUID?)
}

/// Centralizes effective-profile resolution. It reads model/runtime state but
/// never mutates Tabs, Spaces, WebViews, or persistence.
@MainActor
final class ProfileAssignmentPolicy {
    typealias PlacementProfileIDs = (current: UUID?, default: UUID?)

    private let runtimeConnection: TabRuntimePortConnection
    private let spaces: TabSpaceCollectionStateOwner
    private let membership: TabCollectionMembershipOwner
    private let transientTabs: TabTransientTabRegistryOwner

    init(
        runtimeConnection: TabRuntimePortConnection,
        spaces: TabSpaceCollectionStateOwner,
        membership: TabCollectionMembershipOwner,
        transientTabs: TabTransientTabRegistryOwner
    ) {
        self.runtimeConnection = runtimeConnection
        self.spaces = spaces
        self.membership = membership
        self.transientTabs = transientTabs
    }

    func profileExists(_ profileID: UUID) -> Bool {
        let lease = runtimeConnection.captureLease()
        let exists = profileExists(profileID, using: lease)
        guard runtimeConnection.acceptsExactAttachment(lease) else {
            return false
        }
        return exists
    }

    func profileExists(
        _ profileID: UUID,
        using lease: TabRuntimePortLease
    ) -> Bool {
        lease.registry?.profileExists(profileID) ?? false
    }

    func resolvedAssignmentProfile(
        for tab: Tab,
        desiredProfileID: UUID?
    ) -> Profile? {
        let lease = runtimeConnection.captureLease()
        guard runtimeConnection.acceptsExactAttachment(lease) else {
            return nil
        }
        let profile = resolvedAssignmentProfile(
            for: tab,
            desiredProfileID: desiredProfileID,
            using: lease
        )
        guard runtimeConnection.acceptsExactAttachment(lease) else {
            return nil
        }
        return profile
    }

    func resolvedAssignmentProfile(
        for tab: Tab,
        desiredProfileID: UUID?,
        using lease: TabRuntimePortLease
    ) -> Profile? {
        if let desiredProfileID {
            return lease.profile(with: desiredProfileID)
        }
        if let spaceID = tab.spaceId,
           let inheritedProfileID = spaces.profileId(
               for: spaceID
           ), let profile = lease.profile(with: inheritedProfileID) {
            return profile
        }
        if let currentProfileID = lease.currentProfileID,
           let profile = lease.profile(with: currentProfileID) {
            return profile
        }
        if let defaultProfileID = lease.defaultProfileID {
            return lease.profile(with: defaultProfileID)
        }
        return nil
    }

    func placementProfileIDs() -> PlacementProfileIDs {
        let lease = runtimeConnection.captureLease()
        guard runtimeConnection.acceptsExactAttachment(lease) else {
            return (current: nil, default: nil)
        }
        return (current: lease.currentProfileID, default: lease.defaultProfileID)
    }

    func profileIDsForSpaceTransition(
        tab: Tab,
        targetSpaceID: UUID?,
        desiredProfileID: UUID?
    ) -> (current: UUID, target: UUID)? {
        let lease = runtimeConnection.captureLease()
        guard runtimeConnection.acceptsExactAttachment(lease) else {
            return nil
        }
        let profileIDs = profileIDsForSpaceTransition(
            tab: tab,
            targetSpaceID: targetSpaceID,
            desiredProfileID: desiredProfileID,
            using: lease
        )
        guard runtimeConnection.acceptsExactAttachment(lease) else {
            return nil
        }
        return profileIDs
    }

    func profileIDsForSpaceTransition(
        tab: Tab,
        targetSpaceID: UUID?,
        desiredProfileID: UUID?,
        using lease: TabRuntimePortLease
    ) -> (current: UUID, target: UUID)? {
        guard lease.registry != nil,
              runtimeConnection.acceptsExactAttachment(lease),
              tab.spaceId != targetSpaceID,
              tab.profileId == nil,
              let current = tab.spaceId.flatMap(
                  spaces.profileId(for:)
              ) ?? lease.currentProfileID
                  ?? lease.defaultProfileID,
              let target = desiredProfileID
                  ?? targetSpaceID.flatMap(
                      spaces.profileId(for:)
                  )
                  ?? lease.currentProfileID
                  ?? lease.defaultProfileID,
              current != target else {
            return nil
        }
        return (current, target)
    }

    func deletionAssignment(
        for tab: Tab,
        deletedProfileID: UUID,
        fallbackProfileID: UUID,
        using lease: TabRuntimePortLease
    ) -> DeletedProfileTabAssignment {
        if tab.profileId == deletedProfileID {
            if let spaceID = tab.spaceId,
               let inheritedProfileID = spaces.profileId(
                   for: spaceID
               ), inheritedProfileID != deletedProfileID {
                return .assign(nil)
            }
            return .assign(fallbackProfileID)
        }

        let isContextlessDeletedProfile = tab.profileId == nil
            && tab.spaceId == nil
            && resolvedAssignmentProfile(
                for: tab,
                desiredProfileID: nil,
                using: lease
            )?.id == deletedProfileID
        return isContextlessDeletedProfile
            ? .assign(fallbackProfileID)
            : .none
    }

    func allProfileManagedTabs() -> [Tab] {
        var seen: Set<UUID> = []
        return (
            membership.allTabs()
                + Array(transientTabs.auxiliaryMiniWindowTabsByID.values)
        ).filter { seen.insert($0.id).inserted }
    }
}
