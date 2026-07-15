import SumiWebRuntime

/// Presents one exact Space/profile transaction to the WebView replacement
/// pipeline while keeping transition-table ownership inside its service.
@MainActor
final class SpaceProfileReplacementModelParticipant:
    SpaceProfileWebViewReplacementTransaction {
    private enum ModelError: Error { case stale }
    private weak var transaction: SpaceProfileTransaction?
    private weak var owner: SpaceProfileTransitionService?
    private let intent: DeferredWebViewSpaceProfileAssignmentIntent
    private let revision: UInt64
    private var didClaim = false

    init(
        transaction: SpaceProfileTransaction,
        owner: SpaceProfileTransitionService,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        revision: UInt64
    ) {
        self.transaction = transaction
        self.owner = owner
        self.intent = intent
        self.revision = revision
    }

    func validateForStaging() -> Bool {
        guard let transaction, owns(transaction) else { return false }
        return transaction.isCurrentPending(revision: revision)
    }

    func exactTabsForRuntime() -> [Tab]? {
        guard let transaction, owns(transaction) else { return nil }
        return transaction.exactParticipantTabs(revision: revision)
    }

    func stage() throws {
        guard let transaction, owns(transaction),
              transaction.stage(revision: revision) else {
            throw ModelError.stale
        }
    }

    func retainsModelAfterFailedStage() -> Bool {
        transaction?.state == .retainedCleanupConflict
    }

    func stagedModelIsExact() -> Bool {
        guard let transaction, owns(transaction) else { return false }
        return transaction.stagedModelIsExact()
    }

    func canClaimTerminalModel() -> Bool {
        guard let transaction, owns(transaction) else { return false }
        return transaction.canSealCommit()
    }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard let transaction, owns(transaction) else {
            return .terminallyDrained
        }
        let outcome = transaction.sealCommit()
        if outcome == .sealed { didClaim = true }
        return outcome
    }

    func claimedModelIsExact() -> Bool {
        guard didClaim, let transaction, owns(transaction) else { return false }
        return transaction.claimedModelIsExact()
    }

    func publishCommit() {
        guard let transaction, owns(transaction) else { return }
        let intent = intent
        transaction.publishCommit { [weak owner, weak transaction] in
            guard let transaction else { return }
            owner?.replacementModelDidPublishCommit(
                transaction,
                intent: intent
            )
        }
    }

    func rollback() throws {
        guard let transaction, owns(transaction), transaction.rollback() else {
            throw ModelError.stale
        }
    }

    func publishRollback() {
        guard let transaction, owns(transaction) else { return }
        transaction.publishRolledBackModel()
        owner?.replacementModelDidPublishRollback(transaction, intent: intent)
    }

    func canSettleTerminalDrain() -> Bool {
        guard let transaction, owns(transaction) else { return false }
        return transaction.canSettleTerminalDrain()
    }

    func settleTerminalDrain() -> Bool {
        guard let transaction, owns(transaction),
              transaction.settleTerminalDrain() else { return false }
        owner?.replacementModelDidSettleTerminalDrain(
            transaction,
            intent: intent
        )
        return true
    }

    private func owns(_ transaction: SpaceProfileTransaction) -> Bool {
        owner?.ownsReplacementModel(transaction, intent: intent) == true
    }
}
