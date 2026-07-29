import Foundation

@MainActor
final class SpaceRemovalBatchTransaction {
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

    func removeSpaces(
        _ requestedSpaceIDs: [UUID],
        allowingEmptyCatalog: Bool
    ) -> Bool {
        let spaceIDs = Set(requestedSpaceIDs)
        var preparedRetirements: [PreparedSpaceContentRetirement] = []
        var changedWindowsByID: [UUID: BrowserWindowState] = [:]
        var didRemove = false
        transactions.withTransaction {
            guard let runtime = windowStates.runtimeLease(),
                  catalog.canRemove(
                      spaceIDs: spaceIDs,
                      allowingEmptyCatalog: allowingEmptyCatalog
                  ),
                  let plans = contentRetirement.plan(
                      spaceIds: requestedSpaceIDs,
                      using: runtime
                  ),
                  windowStates.accepts(runtime),
                  let retirements = contentRetirement.commit(plans)
            else {
                return
            }
            preparedRetirements = retirements
            catalog.commitRemovals(spaceIDs: spaceIDs)
            didRemove = true
            transactions.requestPublish(scope: .spaces(spaceIDs, catalog: true))
            for retirement in retirements {
                for window in windowStates.reconcile(
                    retirement.footprint,
                    using: runtime
                ) {
                    changedWindowsByID[window.id] = window
                }
            }
        }
        guard let runtime = preparedRetirements.first?.runtime else {
            return didRemove
        }
        let retirements = preparedRetirements
        let windows = changedWindowsByID.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        transactions.runAfterCurrentBatch { [contentRetirement, windowStates] in
            retirements.forEach(contentRetirement.finish)
            windowStates.finish(changedWindows: windows, using: runtime)
        }
        return didRemove
    }
}
