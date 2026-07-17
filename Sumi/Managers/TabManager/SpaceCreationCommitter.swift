import Combine
import Foundation

@MainActor
final class SpaceCreationCommitter {
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let persistence: TabStructuralPersistenceService
    private let changes: ObservableObjectPublisher

    init(
        structuralMutations: TabStructuralCollectionMutationOwner,
        persistence: TabStructuralPersistenceService,
        changes: ObservableObjectPublisher
    ) {
        self.structuralMutations = structuralMutations
        self.persistence = persistence
        self.changes = changes
    }

    func commit(
        _ space: Space,
        to spaces: TabSpaceCollectionStateOwner,
        in transactions: TabStructuralLookupCoordinator
    ) {
        changes.send()
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
