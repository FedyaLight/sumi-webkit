import Foundation

@MainActor
final class SpaceProfileTransitionPublication: SpaceProfileTransitionAvailability {
    private let membership: TabCollectionMembershipOwner
    private let persistence: TabStructuralPersistenceService
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        membership: TabCollectionMembershipOwner,
        persistence: TabStructuralPersistenceService,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.membership = membership
        self.persistence = persistence
        self.structuralLookup = structuralLookup
    }

    func contains(_ tab: Tab, in spaceID: UUID) -> Bool {
        membership.allTabs().contains {
            $0 === tab && $0.spaceId == spaceID
        }
    }

    func publishStructuralMutation(spaceID: UUID) {
        persistence.markAllSpacesStructurallyDirty()
        persistence.markRegularTabsStructurallyDirty(for: spaceID)
        persistence.scheduleStructuralPersistence()
        structuralLookup.requestPublish(scope: .space(
            spaceID,
            catalog: true
        ))
    }
}
