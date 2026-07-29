import Foundation

/// Retires one Space as a single domain transaction: live tab runtimes end,
/// structural collections disappear, and window-local references are repaired.
@MainActor
final class SpaceRemovalService {
    private let transaction: SpaceRemovalBatchTransaction

    init(
        transactions: TabStructuralLookupCoordinator,
        contentRetirement: SpaceContentRetirementService,
        windowStates: DeletedSpaceWindowStateReconciler,
        catalog: SpaceRemovalCatalogCommitter
    ) {
        transaction = SpaceRemovalBatchTransaction(
            transactions: transactions,
            contentRetirement: contentRetirement,
            windowStates: windowStates,
            catalog: catalog
        )
    }

    func removeSpace(_ spaceId: UUID) {
        _ = transaction.removeSpaces(
            [spaceId],
            allowingEmptyCatalog: false
        )
    }

    @discardableResult
    func removeSpacesForProfileRetirement(_ spaceIDs: [UUID]) -> Bool {
        transaction.removeSpaces(
            spaceIDs,
            allowingEmptyCatalog: true
        )
    }
}
