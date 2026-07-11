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
        case conflicted
    }

    private final class Transaction {
        let id: WebViewReplacementTransactionID
        let lease: WebViewReplacementBatchLease
        let tabIDs: Set<UUID>
        let profileIDs: Set<UUID>
        let retiredBeforeBegin: [UUID: WebViewSessionSnapshot]
        let requirementsByWebViewID: [ObjectIdentifier: Requirement]
        let modelRollback: WebViewReplacementModelRollback
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
            modelRollback: @escaping WebViewReplacementModelRollback,
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
            self.modelRollback = modelRollback
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
        modelRollback: @escaping WebViewReplacementModelRollback,
        completion: @escaping @MainActor (
            WebViewReplacementTransactionOutcome
        ) -> Void = { _ in }
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
            modelRollback: modelRollback,
            receipt: receipt,
            completion: completion
        )
        transactionsByID[transactionID] = transaction
        for tabID in tabIDs {
            transactionIDByTabID[tabID] = transactionID
        }

        runtime.quiesceRetired(retired)
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
            complete(transaction, outcome: .abandonedForTerminalShutdown)
            runtime.observeSettlement(
                .abandonedForTerminalShutdown(transaction.id)
            )
        }
    }

    private func commit(
        _ transaction: Transaction
    ) -> WebViewReplacementSettlementStartResult {
        guard transactionsByID[transaction.id] === transaction,
              case .awaitingBindings = transaction.state else {
            return .leaseLost(transaction.id)
        }
        guard runtime.validateCommitLease(transaction.lease) else {
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
            remove(transaction)
            runtime.retireCommitted(retired)
            complete(transaction, outcome: .committed)
            runtime.observeSettlement(.committed(transaction.id))
            return .committed(transaction.id)
        case .conflict:
            markConflicted(transaction)
            return .conflicted(transaction.id)
        case .noLongerActive:
            remove(transaction)
            complete(transaction, outcome: .leaseLost)
            runtime.observeSettlement(.leaseLost(transaction.id))
            return .leaseLost(transaction.id)
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
        switch runtime.rollbackLease(
            transaction.lease,
            transaction.modelRollback
        ) {
        case .rolledBack(let discarded):
            remove(transaction)
            runtime.restoreAfterRollback(
                discarded,
                transaction.retiredBeforeBegin,
                reason
            )
            complete(transaction, outcome: .rolledBack(reason))
            runtime.observeSettlement(.rolledBack(transaction.id, reason))
            return .rolledBack
        case .conflict:
            markConflicted(transaction)
            return .conflicted
        case .noLongerActive:
            remove(transaction)
            complete(transaction, outcome: .leaseLost)
            runtime.observeSettlement(.leaseLost(transaction.id))
            return .leaseLost
        }
    }

    private func markConflicted(_ transaction: Transaction) {
        guard case .awaitingBindings = transaction.state else { return }
        transaction.state = .conflicted
        transaction.timeoutTask?.cancel()
        transaction.timeoutTask = nil
        complete(transaction, outcome: .conflicted)
        runtime.observeSettlement(.conflicted(transaction.id))
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
}
