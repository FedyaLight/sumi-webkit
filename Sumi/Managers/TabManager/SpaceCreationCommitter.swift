import Foundation

@MainActor
final class SpaceCreationCommitter {
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let persistence: TabStructuralPersistenceService

    init(
        structuralMutations: TabStructuralCollectionMutationOwner,
        persistence: TabStructuralPersistenceService
    ) {
        self.structuralMutations = structuralMutations
        self.persistence = persistence
    }

    func commit(
        _ space: Space,
        to spaces: TabSpaceCollectionStateOwner,
        in transactions: TabStructuralLookupCoordinator
    ) {
        spaces.append(space)
        persistence.markAllSpacesStructurallyDirty()
        structuralMutations.setTabs([], for: space.id)
        if spaces.currentSpace == nil {
            spaces.replaceCurrentSpace(space)
        }
        transactions.requestPublish(scope: .space(space.id, catalog: true))
        persistence.scheduleStructuralPersistence()
    }
}
