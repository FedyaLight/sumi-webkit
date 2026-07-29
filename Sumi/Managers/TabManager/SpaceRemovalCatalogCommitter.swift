import Foundation

@MainActor
final class SpaceRemovalCatalogCommitter {
    private let state: TabStateStore
    private let persistence: TabStructuralPersistenceService

    init(
        state: TabStateStore,
        persistence: TabStructuralPersistenceService
    ) {
        self.state = state
        self.persistence = persistence
    }

    func canRemove(spaceIDs: Set<UUID>, allowingEmptyCatalog: Bool) -> Bool {
        guard spaceIDs.isEmpty == false,
              spaceIDs.count == state.spaces.spaces.filter({
                  spaceIDs.contains($0.id)
              }).count else {
            return false
        }
        return allowingEmptyCatalog
            || state.spaces.count - spaceIDs.count >= 1
    }

    func commitRemovals(spaceIDs: Set<UUID>) {
        precondition(
            spaceIDs.count == state.spaces.spaces.filter {
                spaceIDs.contains($0.id)
            }.count
        )
        spaceIDs.forEach(persistence.markSpaceStructurallyDeleted)
        state.spaces.replaceSpaces(
            state.spaces.spaces.filter { spaceIDs.contains($0.id) == false }
        )
        persistence.markAllSpacesStructurallyDirty()
        if state.spaces.currentSpaceId.map(spaceIDs.contains) == true {
            state.spaces.replaceCurrentSpace(state.spaces.firstSpace)
        }
        persistence.scheduleStructuralPersistence()
    }
}
