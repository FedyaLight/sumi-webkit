/// Cross-component invariant checker. It observes identity projections only;
/// canonical WebView ownership remains in placement records and the ledger.
@MainActor
final class WebViewSessionConsistencyValidator {
    private unowned let placements: WebViewSessionPlacementStore
    private unowned let transitions: WebViewOwnershipTransitionLedger
    private unowned let transactions: WebViewReplacementTransactionStore

    init(
        placements: WebViewSessionPlacementStore,
        transitions: WebViewOwnershipTransitionLedger,
        transactions: WebViewReplacementTransactionStore
    ) {
        self.placements = placements
        self.transitions = transitions
        self.transactions = transactions
    }

    func assertConsistency(_ context: StaticString) {
        #if DEBUG
            placements.assertConsistency(context)
            transitions.assertConsistency(context)
            transactions.assertConsistency(context)

            let activeIDs = Set(placements.activeResidences.keys)
            let transitionIDs = Set(transitions.transitionResidences.keys)
            assert(
                activeIDs.isDisjoint(with: transitionIDs),
                "Active and transition ownership overlap during \(context)"
            )
            assert(
                transactions.batchIDs == transitions.openBatchIDs,
                "Replacement and transition batch sets diverged during \(context)"
            )
            for batch in transactions.batches.values {
                for replacement in batch.replacementsByTabID.values {
                    assert(
                        transitions.retirementIsIntact(
                            replacement.retirementLease
                        ),
                        "Replacement retirement diverged during \(context)"
                    )
                }
            }
        #else
            _ = context
        #endif
    }
}
