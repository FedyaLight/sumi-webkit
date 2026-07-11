import Foundation

/// Retires one Space as a single domain transaction: live tab runtimes end,
/// structural collections disappear, and window-local references are repaired.
@MainActor
final class SpaceRemovalService {
    private let state: TabStateStore
    private let persistence: TabStructuralPersistenceService
    private let transactions: TabStructuralLookupCoordinator
    private let contentRetirement: SpaceContentRetirementService
    private let windowStates: DeletedSpaceWindowStateReconciler
    private let announceChange: @MainActor () -> Void

    init(
        state: TabStateStore,
        persistence: TabStructuralPersistenceService,
        transactions: TabStructuralLookupCoordinator,
        contentRetirement: SpaceContentRetirementService,
        windowStates: DeletedSpaceWindowStateReconciler,
        announceChange: @escaping @MainActor () -> Void
    ) {
        self.state = state
        self.persistence = persistence
        self.transactions = transactions
        self.contentRetirement = contentRetirement
        self.windowStates = windowStates
        self.announceChange = announceChange
    }

    func removeSpace(_ spaceId: UUID) {
        var preparedRetirement: PreparedSpaceContentRetirement?
        var changedWindows: [BrowserWindowState] = []
        transactions.withTransaction {
            guard state.spaces.count > 1,
                  let index = state.spaces.index(of: spaceId) else {
                return
            }

            let runtime = windowStates.runtimeLease()
            let retirement = contentRetirement.prepare(
                spaceId: spaceId,
                using: runtime
            )
            preparedRetirement = retirement
            persistence.markSpaceStructurallyDeleted(spaceId)

            announceChange()
            _ = state.spaces.remove(at: index)
            persistence.markAllSpacesStructurallyDirty()
            if state.spaces.currentSpaceId == spaceId {
                state.spaces.replaceCurrentSpace(state.spaces.firstSpace)
            }

            persistence.scheduleStructuralPersistence()
            changedWindows = windowStates.reconcile(
                retirement.footprint,
                using: runtime
            )
        }
        if let retirement = preparedRetirement {
            let windowsToPersist = changedWindows
            transactions.runAfterCurrentBatch { [contentRetirement, windowStates] in
                contentRetirement.finish(retirement)
                windowStates.finish(
                    changedWindows: windowsToPersist,
                    using: retirement.runtime
                )
            }
        }
    }
}
