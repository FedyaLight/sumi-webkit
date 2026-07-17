import Combine
import Foundation

@MainActor
final class SpaceRemovalCatalogCommitter {
    private let state: TabStateStore
    private let persistence: TabStructuralPersistenceService
    private let changes: ObservableObjectPublisher

    init(
        state: TabStateStore,
        persistence: TabStructuralPersistenceService,
        changes: ObservableObjectPublisher
    ) {
        self.state = state
        self.persistence = persistence
        self.changes = changes
    }

    func removalIndex(for spaceID: UUID) -> Int? {
        guard state.spaces.count > 1 else { return nil }
        return state.spaces.index(of: spaceID)
    }

    func commitRemoval(spaceID: UUID, at index: Int) {
        precondition(state.spaces.index(of: spaceID) == index)
        persistence.markSpaceStructurallyDeleted(spaceID)
        changes.send()
        _ = state.spaces.remove(at: index)
        persistence.markAllSpacesStructurallyDirty()
        if state.spaces.currentSpaceId == spaceID {
            state.spaces.replaceCurrentSpace(state.spaces.firstSpace)
        }
        persistence.scheduleStructuralPersistence()
    }
}
