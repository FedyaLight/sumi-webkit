import Foundation

/// Clears one Space as a single domain transaction: live tab runtimes end,
/// structural collections disappear, and window-local references are repaired,
/// while the Space catalog entry itself survives untouched.
@MainActor
final class SpaceClearingService {
    private let transactions: TabStructuralLookupCoordinator
    private let contentRetirement: SpaceContentRetirementService
    private let windowStates: DeletedSpaceWindowStateReconciler
    private let persistence: TabStructuralPersistenceService

    init(
        transactions: TabStructuralLookupCoordinator,
        contentRetirement: SpaceContentRetirementService,
        windowStates: DeletedSpaceWindowStateReconciler,
        persistence: TabStructuralPersistenceService
    ) {
        self.transactions = transactions
        self.contentRetirement = contentRetirement
        self.windowStates = windowStates
        self.persistence = persistence
    }

    func clearSpace(_ spaceId: UUID) {
        var preparedRetirement: PreparedSpaceContentRetirement?
        var changedWindows: [BrowserWindowState] = []
        transactions.withTransaction {
            guard let runtime = windowStates.runtimeLease(),
                  let plan = contentRetirement.plan(
                spaceId: spaceId,
                using: runtime
            ), windowStates.accepts(runtime),
                  let retirement = contentRetirement.commit(plan) else {
                return
            }
            preparedRetirement = retirement
            persistence.scheduleStructuralPersistence()
            changedWindows = windowStates.reconcile(
                retirement.footprint,
                using: runtime,
                spaceSurvives: true
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
