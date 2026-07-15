import Foundation
import WebKit

@MainActor
/// Settles an already-begun repository replacement batch from exact concrete
/// navigation bindings. Provisioning, placement, navigation submission, and
/// physical WebKit effects remain behind injected ports. This service changes
/// only when commit/rollback/abort/timeout settlement policy changes.
public final class WebViewReplacementSettlementService {
    private final class Requirement {
        let token: WebViewReplacementBindingToken
        let webViewWitness: WebViewIdentityWitness
        var isBound = false

        init(
            token: WebViewReplacementBindingToken,
            webView: WKWebView
        ) {
            self.token = token
            webViewWitness = WebViewIdentityWitness(webView)
        }
    }

    private enum TransactionState {
        case awaitingBindings
        case claimingTerminalModel
        case retiringCommitted
        case restoringRollback
        case conflicted
    }

    private final class Transaction {
        let id: WebViewReplacementTransactionID
        let lease: WebViewReplacementBatchLease
        let tabIDs: Set<UUID>
        let profileIDs: Set<UUID>
        let retiredBeforeBegin: [UUID: WebViewSessionSnapshot]
        let requirementsByWebViewID: [ObjectIdentifier: Requirement]
        let model: WebViewReplacementModelParticipant
        let receipt: WebViewReplacementSettlementReceipt
        let completion: @MainActor (
            WebViewReplacementTransactionOutcome
        ) -> Void
        var state: TransactionState = .awaitingBindings
        var timeoutTask: Task<Void, Never>?
        var didCompleteOutcome = false

        init(
            id: WebViewReplacementTransactionID,
            lease: WebViewReplacementBatchLease,
            tabIDs: Set<UUID>,
            profileIDs: Set<UUID>,
            retiredBeforeBegin: [UUID: WebViewSessionSnapshot],
            requirementsByWebViewID: [ObjectIdentifier: Requirement],
            model: WebViewReplacementModelParticipant,
            receipt: WebViewReplacementSettlementReceipt,
            completion: @escaping @MainActor (
                WebViewReplacementTransactionOutcome
            ) -> Void
        ) {
            self.id = id
            self.lease = lease
            self.tabIDs = tabIDs
            self.profileIDs = profileIDs
            self.retiredBeforeBegin = retiredBeforeBegin
            self.requirementsByWebViewID = requirementsByWebViewID
            self.model = model
            self.receipt = receipt
            self.completion = completion
        }

        var allRequiredBindingsCompleted: Bool {
            requirementsByWebViewID.values.allSatisfy(\.isBound)
        }
    }

    private let runtime: WebViewReplacementSettlementRuntime
    private let waitForTimeout: @MainActor () async -> Void
    private var transactionsByID: [
        WebViewReplacementTransactionID: Transaction
    ] = [:]
    private var transactionIDByTabID: [
        UUID: WebViewReplacementTransactionID
    ] = [:]

    public init(
        timeout: Duration = .seconds(15),
        waitForTimeout: (@MainActor () async -> Void)? = nil,
        runtime: WebViewReplacementSettlementRuntime
    ) {
        self.runtime = runtime
        self.waitForTimeout = waitForTimeout ?? {
            try? await Task.sleep(for: timeout)
        }
    }

    var activeTransactionCount: Int { transactionsByID.count }

    /// Registers the lease before any caller schedules asynchronous loads.
    /// `retired` is the exact pre-begin snapshot used for physical quiescence
    /// and semantic restoration if the repository transaction rolls back.
    public func start(
        lease: WebViewReplacementBatchLease,
        tabIDs: Set<UUID>,
        profileIDs: Set<UUID>,
        retired: [UUID: WebViewSessionSnapshot],
        requiredBindings: [WebViewReplacementBindingRequirement],
        model: WebViewReplacementModelParticipant,
        completion: @escaping @MainActor (
            WebViewReplacementTransactionOutcome
        ) -> Void
    ) -> WebViewReplacementSettlementStartResult {
        precondition(tabIDs.isEmpty == false)
        precondition(Set(retired.keys) == tabIDs)
        precondition(
            transactionsByID.values.contains(where: { $0.lease == lease }) == false,
            "A repository replacement lease can have only one settlement service"
        )
        precondition(
            tabIDs.allSatisfy { transactionIDByTabID[$0] == nil },
            "Overlapping replacement transactions must settle before begin"
        )

        let transactionID = WebViewReplacementTransactionID(rawValue: UUID())
        var requirementsByWebViewID: [ObjectIdentifier: Requirement] = [:]
        var bindingTokens: [WebViewReplacementBindingToken] = []
        bindingTokens.reserveCapacity(requiredBindings.count)
        for binding in requiredBindings {
            let webViewID = ObjectIdentifier(binding.webView)
            precondition(
                requirementsByWebViewID[webViewID] == nil,
                "A replacement WebView can require only one exact binding"
            )
            let token = WebViewReplacementBindingToken(
                transactionID: transactionID,
                nonce: UUID(),
                webViewID: webViewID,
                semanticRevision: binding.semanticRevision
            )
            requirementsByWebViewID[webViewID] = Requirement(
                token: token,
                webView: binding.webView
            )
            bindingTokens.append(token)
        }

        let receipt = WebViewReplacementSettlementReceipt(
            transactionID: transactionID,
            bindingTokens: bindingTokens
        )
        let transaction = Transaction(
            id: transactionID,
            lease: lease,
            tabIDs: tabIDs,
            profileIDs: profileIDs,
            retiredBeforeBegin: retired,
            requirementsByWebViewID: requirementsByWebViewID,
            model: model,
            receipt: receipt,
            completion: completion
        )
        transactionsByID[transactionID] = transaction
        for tabID in tabIDs {
            transactionIDByTabID[tabID] = transactionID
        }

        runtime.quiesceRetired(retired)
        guard transactionsByID[transactionID] === transaction,
              case .awaitingBindings = transaction.state else {
            return .leaseLost(transactionID)
        }
        if requirementsByWebViewID.isEmpty {
            return commit(transaction)
        }

        transaction.timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await waitForTimeout()
            guard Task.isCancelled == false else { return }
            _ = fail(transactionID, reason: .timedOut)
        }
        return .started(receipt)
    }

    /// Retains a failed admission whose model compensation could not complete.
    /// The repository keeps both generations under the claimed rollback lease;
    /// this service keeps the exact model participant until terminal drain can
    /// settle both ownership domains together.
    public func retainConflictedAdmission(
        lease: WebViewReplacementBatchLease,
        tabIDs: Set<UUID>,
        profileIDs: Set<UUID>,
        retired: [UUID: WebViewSessionSnapshot],
        model: WebViewReplacementModelParticipant
    ) {
        precondition(tabIDs.isEmpty == false)
        precondition(Set(retired.keys) == tabIDs)
        precondition(
            transactionsByID.values.contains(where: { $0.lease == lease })
                == false,
            "A repository replacement lease can have only one settlement owner"
        )
        precondition(
            tabIDs.allSatisfy { transactionIDByTabID[$0] == nil },
            "Overlapping replacement admissions cannot share quarantine"
        )

        let transactionID = WebViewReplacementTransactionID(rawValue: UUID())
        let receipt = WebViewReplacementSettlementReceipt(
            transactionID: transactionID,
            bindingTokens: []
        )
        let transaction = Transaction(
            id: transactionID,
            lease: lease,
            tabIDs: tabIDs,
            profileIDs: profileIDs,
            retiredBeforeBegin: retired,
            requirementsByWebViewID: [:],
            model: model,
            receipt: receipt,
            completion: { _ in }
        )
        transaction.state = .conflicted
        transactionsByID[transactionID] = transaction
        for tabID in tabIDs {
            transactionIDByTabID[tabID] = transactionID
        }

        runtime.quiesceRetired(retired)
        guard transactionsByID[transactionID] === transaction else { return }
        completeConflict(transaction)
    }

    /// Accepts only the transaction nonce, exact live WebView, semantic
    /// revision, and concrete navigation identity captured by the matching
    /// submission callback.
    @discardableResult
    public func markBound(
        _ token: WebViewReplacementBindingToken,
        binding: WebViewReplacementNavigationBinding
    ) -> WebViewReplacementBindingAcceptance {
        guard let transaction = transactionsByID[token.transactionID],
              case .awaitingBindings = transaction.state,
              let requirement = transaction.requirementsByWebViewID[
                token.webViewID
              ],
              requirement.token == token,
              requirement.isBound == false,
              requirement.webViewWitness.matches(binding.webView),
              binding.semanticRevision == token.semanticRevision,
              binding.navigationID == ObjectIdentifier(
                binding.navigationLifetime
              ) else {
            return .ignored
        }

        requirement.isBound = true
        guard transaction.allRequiredBindingsCompleted else {
            return .accepted
        }
        switch commit(transaction) {
        case .committed:
            return .committed
        case .rolledBack(_, let reason):
            return .rolledBack(reason)
        case .conflicted:
            return .conflicted
        case .leaseLost:
            return .leaseLost
        case .started:
            preconditionFailure("A completed binding set cannot remain started")
        }
    }

    @discardableResult
    public func fail(
        _ token: WebViewReplacementBindingToken,
        reason: WebViewReplacementBindingFailureReason
    ) -> WebViewReplacementSettlementAttempt {
        guard let transaction = transactionsByID[token.transactionID],
              let requirement = transaction.requirementsByWebViewID[
                token.webViewID
              ],
              requirement.token == token else {
            return .ignored
        }
        return rollback(
            transaction,
            reason: .bindingFailure(reason)
        )
    }

    @discardableResult
    public func fail(
        _ transactionID: WebViewReplacementTransactionID,
        reason: WebViewReplacementBindingFailureReason
    ) -> WebViewReplacementSettlementAttempt {
        guard let transaction = transactionsByID[transactionID] else {
            return .ignored
        }
        return rollback(
            transaction,
            reason: .bindingFailure(reason)
        )
    }

    @discardableResult
    public func abortForProfiles(
        _ profileIDs: Set<UUID>,
        reason: WebViewReplacementAbortReason
    ) -> Int {
        guard profileIDs.isEmpty == false else { return 0 }
        let transactions = transactionsByID.values
            .filter {
                $0.profileIDs.isDisjoint(with: profileIDs) == false
                    && isAwaitingBindings($0)
            }
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        return transactions.reduce(into: 0) { count, transaction in
            if rollback(transaction, reason: .abort(reason)) == .rolledBack {
                count += 1
            }
        }
    }

    @discardableResult
    public func abortForTabs(
        _ tabIDs: Set<UUID>,
        reason: WebViewReplacementAbortReason
    ) -> Int {
        guard tabIDs.isEmpty == false else { return 0 }
        let transactions = transactionsByID.values
            .filter {
                $0.tabIDs.isDisjoint(with: tabIDs) == false
                    && isAwaitingBindings($0)
            }
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        return transactions.reduce(into: 0) { count, transaction in
            if rollback(transaction, reason: .abort(reason)) == .rolledBack {
                count += 1
            }
        }
    }

    @discardableResult
    public func abortAll(reason: WebViewReplacementAbortReason) -> Int {
        let transactions = transactionsByID.values
            .filter(isAwaitingBindings)
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        return transactions.reduce(into: 0) { count, transaction in
            if rollback(transaction, reason: .abort(reason)) == .rolledBack {
                count += 1
            }
        }
    }

    /// Terminal repository drain owns both generations. This method only
    /// prevents late timeout/binding callbacks from invoking settlement or
    /// physical cleanup a second time.
    public func resetForTerminalShutdown() {
        let transactions = transactionsByID.values.sorted {
            $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
        transactionsByID.removeAll()
        transactionIDByTabID.removeAll()
        for transaction in transactions {
            transaction.timeoutTask?.cancel()
            transaction.timeoutTask = nil
            if transaction.model.canSettleTerminalDrain(),
               transaction.model.settleTerminalDrain() {
                complete(transaction, outcome: .abandonedForTerminalShutdown)
                runtime.observeSettlement(
                    .abandonedForTerminalShutdown(transaction.id)
                )
            } else {
                complete(transaction, outcome: .conflicted)
                runtime.observeSettlement(.conflicted(transaction.id))
            }
        }
    }

    private func commit(
        _ transaction: Transaction
    ) -> WebViewReplacementSettlementStartResult {
        guard transactionsByID[transaction.id] === transaction,
              case .awaitingBindings = transaction.state else {
            return .leaseLost(transaction.id)
        }
        let commitLeaseIsValid = runtime.validateCommitLease(transaction.lease)
        guard transactionsByID[transaction.id] === transaction else {
            return .leaseLost(transaction.id)
        }
        guard commitLeaseIsValid else {
            let reason = WebViewReplacementRollbackReason
                .commitValidationFailed
            switch rollback(transaction, reason: reason) {
            case .rolledBack:
                return .rolledBack(transaction.id, reason)
            case .conflicted:
                return .conflicted(transaction.id)
            case .leaseLost, .ignored:
                return .leaseLost(transaction.id)
            }
        }
        let stagedModelIsExact = transaction.model.stagedModelIsExact()
        guard transactionsByID[transaction.id] === transaction else {
            return .leaseLost(transaction.id)
        }
        guard stagedModelIsExact else {
            markConflicted(transaction)
            return .conflicted(transaction.id)
        }
        let canClaimTerminalModel = transaction.model.canClaimTerminalModel()
        guard transactionsByID[transaction.id] === transaction else {
            return .leaseLost(transaction.id)
        }
        guard canClaimTerminalModel else {
            let reason = WebViewReplacementRollbackReason
                .commitValidationFailed
            switch rollback(transaction, reason: reason) {
            case .rolledBack:
                return .rolledBack(transaction.id, reason)
            case .conflicted:
                return .conflicted(transaction.id)
            case .leaseLost, .ignored:
                return .leaseLost(transaction.id)
            }
        }
        switch runtime.commitLease(transaction.lease) {
        case .committed(let retired):
            guard transactionsByID[transaction.id] === transaction else {
                runtime.retireCommitted(retired)
                return .leaseLost(transaction.id)
            }
            let committedModelIsExact = transaction.model.stagedModelIsExact()
            guard transactionsByID[transaction.id] === transaction else {
                runtime.retireCommitted(retired)
                return .leaseLost(transaction.id)
            }
            guard committedModelIsExact else {
                return retireCommittedAndQuarantine(transaction, retired: retired)
            }
            let committedModelCanBeClaimed = transaction.model
                .canClaimTerminalModel()
            guard transactionsByID[transaction.id] === transaction else {
                runtime.retireCommitted(retired)
                return .leaseLost(transaction.id)
            }
            guard committedModelCanBeClaimed else {
                return retireCommittedAndQuarantine(transaction, retired: retired)
            }
            transaction.state = .claimingTerminalModel
            let claimOutcome = transaction.model.claimTerminalModel()
            guard transactionsByID[transaction.id] === transaction else {
                // A reentrant terminal reset cannot own the predecessor after
                // repository commit returned it to this settlement service.
                runtime.retireCommitted(retired)
                return .leaseLost(transaction.id)
            }
            guard claimOutcome == .sealed else {
                return retireCommittedAndQuarantine(transaction, retired: retired)
            }
            let claimedModelIsExact = transaction.model.claimedModelIsExact()
            guard transactionsByID[transaction.id] === transaction else {
                runtime.retireCommitted(retired)
                return .leaseLost(transaction.id)
            }
            guard claimedModelIsExact else {
                return retireCommittedAndQuarantine(transaction, retired: retired)
            }
            transaction.state = .retiringCommitted
            runtime.retireCommitted(retired)
            guard transactionsByID[transaction.id] === transaction else {
                // Terminal reset completed the abandoned transaction while
                // this frame still owned destruction of the committed
                // predecessor returned by the repository.
                return .leaseLost(transaction.id)
            }
            let retiredModelIsExact = transaction.model.claimedModelIsExact()
            guard transactionsByID[transaction.id] === transaction else {
                return .leaseLost(transaction.id)
            }
            guard retiredModelIsExact else {
                retainCommittedConflict(transaction)
                return .conflicted(transaction.id)
            }
            remove(transaction)
            complete(transaction, outcome: .committed)
            runtime.observeSettlement(.committed(transaction.id))
            return .committed(transaction.id)
        case .conflict:
            guard transactionsByID[transaction.id] === transaction else {
                return .leaseLost(transaction.id)
            }
            markConflicted(transaction)
            return .conflicted(transaction.id)
        case .noLongerActive:
            guard transactionsByID[transaction.id] === transaction else {
                return .leaseLost(transaction.id)
            }
            markConflicted(transaction)
            return .conflicted(transaction.id)
        }
    }

    private func rollback(
        _ transaction: Transaction,
        reason: WebViewReplacementRollbackReason
    ) -> WebViewReplacementSettlementAttempt {
        guard transactionsByID[transaction.id] === transaction,
              case .awaitingBindings = transaction.state else {
            return .ignored
        }
        // Rollback is a model write, not a harmless cleanup. If app-owned
        // staged evidence drifted while bindings were pending, neither the
        // repository nor the model may compensate against an alias/newer
        // value. Keep both generations quarantined for terminal ownership.
        let stagedModelIsExact = transaction.model.stagedModelIsExact()
        guard transactionsByID[transaction.id] === transaction else {
            return .leaseLost
        }
        guard stagedModelIsExact else {
            markConflicted(transaction)
            return .conflicted
        }
        let rollbackResult = runtime.rollbackLease(
            transaction.lease,
            transaction.model.rollback
        )
        guard transactionsByID[transaction.id] === transaction else {
            return .leaseLost
        }
        switch rollbackResult {
        case .rolledBack(let discarded):
            transaction.state = .restoringRollback
            runtime.restoreAfterRollback(
                discarded,
                transaction.retiredBeforeBegin,
                reason
            )
            guard transactionsByID[transaction.id] === transaction else {
                return .leaseLost
            }
            remove(transaction)
            complete(transaction, outcome: .rolledBack(reason))
            runtime.observeSettlement(.rolledBack(transaction.id, reason))
            return .rolledBack
        case .terminallyDrained:
            return settleAfterRepositoryTerminalDrain(transaction)
                ? .leaseLost
                : .conflicted
        case .modelRollbackFailed:
            markConflicted(transaction)
            return .conflicted
        case .conflict:
            markConflicted(transaction)
            return .conflicted
        case .noLongerActive:
            markConflicted(transaction)
            return .conflicted
        }
    }

    private func settleAfterRepositoryTerminalDrain(
        _ transaction: Transaction
    ) -> Bool {
        guard transactionsByID[transaction.id] === transaction else {
            return true
        }
        remove(transaction)
        guard transaction.model.canSettleTerminalDrain(),
              transaction.model.settleTerminalDrain() else {
            complete(transaction, outcome: .conflicted)
            runtime.observeSettlement(.conflicted(transaction.id))
            return false
        }
        complete(transaction, outcome: .abandonedForTerminalShutdown)
        runtime.observeSettlement(.abandonedForTerminalShutdown(transaction.id))
        return true
    }

    private func markConflicted(_ transaction: Transaction) {
        guard transactionsByID[transaction.id] === transaction,
              case .awaitingBindings = transaction.state else { return }
        transaction.state = .conflicted
        transaction.timeoutTask?.cancel()
        transaction.timeoutTask = nil
        completeConflict(transaction)
    }

    private func retireCommittedAndQuarantine(
        _ transaction: Transaction,
        retired: [UUID: WebViewSessionSnapshot]
    ) -> WebViewReplacementSettlementStartResult {
        transaction.state = .retiringCommitted
        runtime.retireCommitted(retired)
        guard transactionsByID[transaction.id] === transaction else {
            return .leaseLost(transaction.id)
        }
        retainCommittedConflict(transaction)
        return .conflicted(transaction.id)
    }

    private func retainCommittedConflict(_ transaction: Transaction) {
        guard transactionsByID[transaction.id] === transaction else { return }
        transaction.state = .conflicted
        transaction.timeoutTask?.cancel()
        transaction.timeoutTask = nil
        completeConflict(transaction)
    }

    private func remove(_ transaction: Transaction) {
        guard transactionsByID[transaction.id] === transaction else { return }
        transactionsByID.removeValue(forKey: transaction.id)
        for tabID in transaction.tabIDs
            where transactionIDByTabID[tabID] == transaction.id {
            transactionIDByTabID.removeValue(forKey: tabID)
        }
        transaction.timeoutTask?.cancel()
        transaction.timeoutTask = nil
    }

    private func isAwaitingBindings(_ transaction: Transaction) -> Bool {
        if case .awaitingBindings = transaction.state { return true }
        return false
    }

    private func complete(
        _ transaction: Transaction,
        outcome: WebViewReplacementTransactionOutcome
    ) {
        guard transaction.didCompleteOutcome == false else { return }
        transaction.didCompleteOutcome = true
        transaction.receipt.complete(with: outcome)
        transaction.completion(outcome)
    }

    private func completeConflict(_ transaction: Transaction) {
        guard transaction.didCompleteOutcome == false else { return }
        transaction.didCompleteOutcome = true
        transaction.receipt.complete(with: .conflicted)
        runtime.observeSettlement(.conflicted(transaction.id))
        transaction.completion(.conflicted)
    }
}
