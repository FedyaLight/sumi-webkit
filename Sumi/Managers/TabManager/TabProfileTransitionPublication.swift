import Foundation

/// Owns the structural facts and publication effects needed when one Tab's
/// profile transition settles.
@MainActor
final class TabProfileTransitionPublication {
    private let spaces: TabSpaceCollectionStateOwner
    private let membership: TabCollectionMembershipOwner
    private let persistence: TabStructuralPersistenceService
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        spaces: TabSpaceCollectionStateOwner,
        membership: TabCollectionMembershipOwner,
        persistence: TabStructuralPersistenceService,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.spaces = spaces
        self.membership = membership
        self.persistence = persistence
        self.structuralLookup = structuralLookup
    }

    func profileID(for spaceID: UUID) -> UUID? {
        spaces.profileId(for: spaceID)
    }

    func containsExact(_ tab: Tab) -> Bool {
        membership.allTabs().contains {
            $0 === tab && $0.spaceId == tab.spaceId
        }
    }

    func publishStructuralMutation(for tab: Tab) {
        if let spaceID = tab.spaceId {
            persistence.markRegularTabsStructurallyDirty(for: spaceID)
        }
        persistence.scheduleStructuralPersistence()
        structuralLookup.requestPublish(
            scope: tab.spaceId.map { .space($0) } ?? .runtimeOnly
        )
    }
}
