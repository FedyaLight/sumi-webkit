import Foundation
import WebKit

public struct WebViewReplacementTransactionID: Equatable, Hashable, Sendable {
    public let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct WebViewReplacementBindingToken: Equatable, Hashable, Sendable {
    public let transactionID: WebViewReplacementTransactionID
    public let nonce: UUID
    public let webViewID: ObjectIdentifier
    public let semanticRevision: UInt64

    init(
        transactionID: WebViewReplacementTransactionID,
        nonce: UUID,
        webViewID: ObjectIdentifier,
        semanticRevision: UInt64
    ) {
        self.transactionID = transactionID
        self.nonce = nonce
        self.webViewID = webViewID
        self.semanticRevision = semanticRevision
    }
}

public struct WebViewReplacementBindingRequirement {
    public let webView: WKWebView
    public let semanticRevision: UInt64

    public init(webView: WKWebView, semanticRevision: UInt64) {
        self.webView = webView
        self.semanticRevision = semanticRevision
    }
}

/// Proof supplied immediately after a normal-tab load returns `.submitted`.
/// The navigation identity and lifetime must describe the same exact object.
public struct WebViewReplacementNavigationBinding {
    public let webView: WKWebView
    public let semanticRevision: UInt64
    public let navigationID: ObjectIdentifier
    public let navigationLifetime: AnyObject

    public init(
        webView: WKWebView,
        semanticRevision: UInt64,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) {
        self.webView = webView
        self.semanticRevision = semanticRevision
        self.navigationID = navigationID
        self.navigationLifetime = navigationLifetime
    }
}

public enum WebViewReplacementBindingFailureReason: Equatable, Sendable {
    case missingPreparation
    case missingNavigator
    case submissionFailed
    case alreadyScheduled
    case stale
    case cancelled
    case timedOut
}

public enum WebViewReplacementAbortReason: Equatable, Sendable {
    case superseded
    case destructiveDataCleanup
    case profileTransition
    case windowDeparture
    case tabDeparture
    case explicit
}

public enum WebViewReplacementRollbackReason: Equatable, Sendable {
    case bindingFailure(WebViewReplacementBindingFailureReason)
    case abort(WebViewReplacementAbortReason)
    /// App-owned evidence required to publish the replacement changed while
    /// the repository lease was awaiting its final navigation bindings.
    case commitValidationFailed
}

public enum WebViewReplacementTransactionOutcome: Equatable {
    case committed
    case rolledBack(WebViewReplacementRollbackReason)
    case conflicted
    case leaseLost
    case abandonedForTerminalShutdown
}

@MainActor
public final class WebViewReplacementSettlementReceipt {
    public let transactionID: WebViewReplacementTransactionID
    public let bindingTokens: [WebViewReplacementBindingToken]
    private var outcome: WebViewReplacementTransactionOutcome?
    private var waiters: [
        UUID: CheckedContinuation<WebViewReplacementTransactionOutcome?, Never>
    ] = [:]

    init(
        transactionID: WebViewReplacementTransactionID,
        bindingTokens: [WebViewReplacementBindingToken]
    ) {
        self.transactionID = transactionID
        self.bindingTokens = bindingTokens
    }

    public func bindingToken(
        for webView: WKWebView
    ) -> WebViewReplacementBindingToken? {
        let webViewID = ObjectIdentifier(webView)
        return bindingTokens.first { $0.webViewID == webViewID }
    }

    /// Cancelling the caller removes only this waiter. The replacement lease,
    /// binding timeout, and repository settlement continue independently.
    public func waitForSettlement() async -> WebViewReplacementTransactionOutcome? {
        if let outcome { return outcome }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else if let outcome {
                    continuation.resume(returning: outcome)
                } else {
                    waiters[waiterID] = continuation
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelWaiter(waiterID)
            }
        }
    }

    func complete(with outcome: WebViewReplacementTransactionOutcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        let pending = waiters.values
        waiters.removeAll()
        pending.forEach { $0.resume(returning: outcome) }
    }

    private func cancelWaiter(_ waiterID: UUID) {
        waiters.removeValue(forKey: waiterID)?.resume(returning: nil)
    }
}

public enum WebViewReplacementSettlementStartResult {
    case started(WebViewReplacementSettlementReceipt)
    case committed(WebViewReplacementTransactionID)
    case rolledBack(
        WebViewReplacementTransactionID,
        WebViewReplacementRollbackReason
    )
    case conflicted(WebViewReplacementTransactionID)
    case leaseLost(WebViewReplacementTransactionID)
}

public enum WebViewReplacementBindingAcceptance: Equatable {
    case ignored
    case accepted
    case committed
    case rolledBack(WebViewReplacementRollbackReason)
    case conflicted
    case leaseLost
}

public enum WebViewReplacementSettlementAttempt: Equatable {
    case rolledBack
    case conflicted
    case leaseLost
    case ignored
}

public enum WebViewReplacementSettlementEvent: Equatable {
    case committed(WebViewReplacementTransactionID)
    case rolledBack(
        WebViewReplacementTransactionID,
        WebViewReplacementRollbackReason
    )
    case conflicted(WebViewReplacementTransactionID)
    case leaseLost(WebViewReplacementTransactionID)
    case abandonedForTerminalShutdown(WebViewReplacementTransactionID)
}

public typealias WebViewReplacementModelRollback = @MainActor () throws -> Void

/// Result of the exact model/runtime claim made after the repository accepts
/// a replacement commit but before any retired WebView is physically torn
/// down. A terminal drain owns the replacement generation; the settlement
/// service still destroys the already-returned predecessor generation before
/// reporting lease loss.
public enum WebViewReplacementTerminalModelClaimOutcome: Equatable {
    case sealed
    case terminallyDrained
}

public typealias WebViewReplacementTerminalModelClaim = @MainActor () ->
    WebViewReplacementTerminalModelClaimOutcome

/// Exact app-model participant for one repository replacement. The explicit
/// `noExternalModel` enum case below is the only intentional no-op path.
@MainActor
public protocol WebViewReplacementModelTransaction: AnyObject {
    func validateForStaging() -> Bool
    func stage() throws
    func retainsModelAfterFailedStage() -> Bool
    func stagedModelIsExact() -> Bool
    func canClaimTerminalModel() -> Bool
    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome
    func claimedModelIsExact() -> Bool
    func publishCommit()
    func rollback() throws
    func publishRollback()
    func canSettleTerminalDrain() -> Bool
    /// Terminal repository ownership makes rollback impossible. The exact
    /// retained app-model witnesses must still leave pending/staged state.
    func settleTerminalDrain() -> Bool
}

@MainActor
public enum WebViewReplacementModelParticipant {
    case noExternalModel
    case transaction(any WebViewReplacementModelTransaction)

    public func validateForStaging() -> Bool {
        switch self {
        case .noExternalModel: true
        case .transaction(let transaction): transaction.validateForStaging()
        }
    }

    public func stage() throws {
        guard case .transaction(let transaction) = self else { return }
        try transaction.stage()
    }

    public func retainsModelAfterFailedStage() -> Bool {
        switch self {
        case .noExternalModel: false
        case .transaction(let transaction):
            transaction.retainsModelAfterFailedStage()
        }
    }

    public func stagedModelIsExact() -> Bool {
        switch self {
        case .noExternalModel: true
        case .transaction(let transaction): transaction.stagedModelIsExact()
        }
    }

    public func canClaimTerminalModel() -> Bool {
        switch self {
        case .noExternalModel: true
        case .transaction(let transaction):
            transaction.canClaimTerminalModel()
        }
    }

    public func claimTerminalModel()
        -> WebViewReplacementTerminalModelClaimOutcome {
        switch self {
        case .noExternalModel: .sealed
        case .transaction(let transaction):
            transaction.claimTerminalModel()
        }
    }

    public func claimedModelIsExact() -> Bool {
        switch self {
        case .noExternalModel: true
        case .transaction(let transaction): transaction.claimedModelIsExact()
        }
    }

    public func publishCommit() {
        guard case .transaction(let transaction) = self else { return }
        transaction.publishCommit()
    }

    public func rollback() throws {
        guard case .transaction(let transaction) = self else { return }
        try transaction.rollback()
    }

    public func publishRollback() {
        guard case .transaction(let transaction) = self else { return }
        transaction.publishRollback()
    }

    public func canSettleTerminalDrain() -> Bool {
        guard case .transaction(let transaction) = self else { return true }
        return transaction.canSettleTerminalDrain()
    }

    public func settleTerminalDrain() -> Bool {
        guard case .transaction(let transaction) = self else { return true }
        return transaction.settleTerminalDrain()
    }
}

/// Narrow port between settlement policy and app-owned repository/physical
/// effects. The service neither provisions WebViews nor submits navigation.
public struct WebViewReplacementSettlementRuntime {
    public let validateCommitLease: @MainActor (
        WebViewReplacementBatchLease
    ) -> Bool
    public let commitLease: @MainActor (
        WebViewReplacementBatchLease
    ) -> WebViewReplacementBatchCommitResult
    public let rollbackLease: @MainActor (
        WebViewReplacementBatchLease,
        WebViewReplacementModelRollback
    ) -> WebViewReplacementBatchRollbackResult
    public let quiesceRetired: @MainActor (
        [UUID: WebViewSessionSnapshot]
    ) -> Void
    public let retireCommitted: @MainActor (
        [UUID: WebViewSessionSnapshot]
    ) -> Void
    public let restoreAfterRollback: @MainActor (
        _ discarded: [UUID: WebViewSessionSnapshot],
        _ retiredBeforeBegin: [UUID: WebViewSessionSnapshot],
        _ reason: WebViewReplacementRollbackReason
    ) -> Void
    public let observeSettlement: @MainActor (
        WebViewReplacementSettlementEvent
    ) -> Void

    public init(
        validateCommitLease: @escaping @MainActor (
            WebViewReplacementBatchLease
        ) -> Bool,
        commitLease: @escaping @MainActor (
            WebViewReplacementBatchLease
        ) -> WebViewReplacementBatchCommitResult,
        rollbackLease: @escaping @MainActor (
            WebViewReplacementBatchLease,
            WebViewReplacementModelRollback
        ) -> WebViewReplacementBatchRollbackResult,
        quiesceRetired: @escaping @MainActor (
            [UUID: WebViewSessionSnapshot]
        ) -> Void,
        retireCommitted: @escaping @MainActor (
            [UUID: WebViewSessionSnapshot]
        ) -> Void,
        restoreAfterRollback: @escaping @MainActor (
            [UUID: WebViewSessionSnapshot],
            [UUID: WebViewSessionSnapshot],
            WebViewReplacementRollbackReason
        ) -> Void,
        observeSettlement: @escaping @MainActor (
            WebViewReplacementSettlementEvent
        ) -> Void
    ) {
        self.validateCommitLease = validateCommitLease
        self.commitLease = commitLease
        self.rollbackLease = rollbackLease
        self.quiesceRetired = quiesceRetired
        self.retireCommitted = retireCommitted
        self.restoreAfterRollback = restoreAfterRollback
        self.observeSettlement = observeSettlement
    }
}
