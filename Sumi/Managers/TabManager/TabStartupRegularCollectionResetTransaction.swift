import Foundation

@MainActor
final class TabStartupRegularCollectionResetTransaction {
    private let state: TabStateStore
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let persistence: TabStructuralPersistenceService

    init(
        state: TabStateStore,
        structuralMutations: TabStructuralCollectionMutationOwner,
        persistence: TabStructuralPersistenceService
    ) {
        self.state = state
        self.structuralMutations = structuralMutations
        self.persistence = persistence
    }

    func reset() {
        for space in state.spaces.spaces {
            structuralMutations.setTabs([], for: space.id)
            if space.activeTabId != nil {
                space.activeTabId = nil
                persistence.markSpacesSnapshotDirty()
            }
        }
        state.selection.replaceCurrentTab(nil)
        persistence.scheduleStructuralPersistence()
    }
}
