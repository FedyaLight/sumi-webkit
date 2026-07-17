import Foundation

/// Retires one exact inactive Tab whose WebExtension creation transaction did
/// not commit. This is not a user close and never captures recently-closed UI.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabDiscardService {
    private let transactions: TabStructuralLookupCoordinator
    private let residenceRemoval: ExtensionRequestedTabResidenceRemovalTransaction
    private let runtimeSettlement: ExtensionRequestedTabRuntimeSettlementTransaction
    private let selectionRestoration: ExtensionRequestedTabSelectionRestoration

    init(
        transactions: TabStructuralLookupCoordinator,
        residenceRemoval: ExtensionRequestedTabResidenceRemovalTransaction,
        runtimeSettlement: ExtensionRequestedTabRuntimeSettlementTransaction,
        selectionRestoration: ExtensionRequestedTabSelectionRestoration
    ) {
        self.transactions = transactions
        self.residenceRemoval = residenceRemoval
        self.runtimeSettlement = runtimeSettlement
        self.selectionRestoration = selectionRestoration
    }

    @discardableResult
    func discard(
        _ tab: Tab,
        restoringSelectionTo tabID: UUID?
    ) -> Bool {
        transactions.withTransaction {
            let selectionWitness = selectionRestoration.capture(for: tab)
            let needsExtensionClose = tab.extensionPageRuntimeOwner
                .hasAnyDidOpenTabNotification()
            guard let removal = residenceRemoval.remove(
                tab,
                notifyingExtensionClose: needsExtensionClose
            ) else { return false }
            runtimeSettlement.settle(
                removal,
                notifyingExtensionClose: needsExtensionClose,
                restoreSelection: {
                    selectionRestoration.restore(selectionWitness, to: tabID)
                }
            )
            return true
        }
    }
}
