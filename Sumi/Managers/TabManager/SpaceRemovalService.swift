import Foundation

/// Retires one Space as a single domain transaction: live tab runtimes end,
/// structural collections disappear, and window-local references are repaired.
@MainActor
final class SpaceRemovalService {
    private let transactions: TabStructuralLookupCoordinator
    private let contentRetirement: SpaceContentRetirementService
    private let windowStates: DeletedSpaceWindowStateReconciler
    private let catalog: SpaceRemovalCatalogCommitter

    init(
        transactions: TabStructuralLookupCoordinator,
        contentRetirement: SpaceContentRetirementService,
        windowStates: DeletedSpaceWindowStateReconciler,
        catalog: SpaceRemovalCatalogCommitter
    ) {
        self.transactions = transactions
        self.contentRetirement = contentRetirement
        self.windowStates = windowStates
        self.catalog = catalog
    }

    func removeSpace(_ spaceId: UUID) {
        var preparedRetirement: PreparedSpaceContentRetirement?
        var changedWindows: [BrowserWindowState] = []
        transactions.withTransaction {
            guard let index = catalog.removalIndex(for: spaceId) else {
                return
            }

            guard let runtime = windowStates.runtimeLease(),
                  let plan = contentRetirement.plan(
                spaceId: spaceId,
                using: runtime
            ), windowStates.accepts(runtime),
                  let retirement = contentRetirement.commit(plan) else {
                return
            }
            preparedRetirement = retirement
            catalog.commitRemoval(spaceID: spaceId, at: index)
            transactions.requestPublish(scope: .space(spaceId, catalog: true))
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
