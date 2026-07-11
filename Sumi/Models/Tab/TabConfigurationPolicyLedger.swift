import Foundation
import ObjectiveC.runtime
import SumiDomain
import WebKit

/// Committed configuration plan for the canonical WebView generation.
///
/// Configuration construction only creates receipts. The ledger changes after
/// canonical placement commits, so provisional WebViews and failed replacement
/// transactions cannot publish policy that never became active.
@MainActor
final class TabConfigurationPolicyLedger {
    enum CommitRole: Equatable {
        /// Installs the only canonical generation or replaces the whole one.
        case canonicalGeneration
        /// Adds a physical clone to an already-canonical generation.
        case additionalClone
    }

    private(set) var committedState: TabConfigurationPolicyState = .unknown
    private(set) var revision: UInt64 = 0
    private var nextPreparationSequence: UInt64 = 0
    private var latestCommittedPreparationSequence: UInt64 = 0

    var protectionAttachment: SumiProtectionAttachmentState? {
        committedState.protectionAttachment
    }

    var safariContentBlockerAttachment:
        SumiSafariContentBlockerAttachmentState? {
        committedState.safariContentBlockerAttachment
    }

    func prepare(
        _ state: TabConfigurationPolicyState,
        expectedSessionGeneration: UInt64
    ) -> PreparedConfigurationPolicyChange {
        nextPreparationSequence &+= 1
        return PreparedConfigurationPolicyChange(
            ledger: self,
            state: state,
            baseRevision: revision,
            sequence: nextPreparationSequence,
            expectedSessionGeneration: expectedSessionGeneration
        )
    }

    fileprivate func canCommit(
        _ receipts: [PreparedConfigurationPolicyChange],
        as role: CommitRole
    ) -> Bool {
        guard let first = receipts.first,
              receipts.allSatisfy({
                  $0.ledger === self
                      && $0.phase == .prepared
                      && $0.state == first.state
              }) else {
            return false
        }

        if role == .additionalClone {
            return committedState != .unknown
                && committedState.fingerprint == first.state.fingerprint
        }

        let changesCommittedState = committedState != first.state
        let isStale = receipts.contains {
            $0.sequence <= latestCommittedPreparationSequence
                || $0.baseRevision != revision
        }

        // An old receipt may confirm an already-committed identical plan, but
        // it can never overwrite a newer generation with another policy.
        return !isStale || !changesCommittedState
    }

    fileprivate func commit(
        _ receipts: [PreparedConfigurationPolicyChange],
        as role: CommitRole
    ) -> Bool {
        guard canCommit(receipts, as: role),
              let first = receipts.first else {
            receipts.forEach { $0.finish(as: .cancelled) }
            return false
        }

        let newestSequence = receipts.map(\.sequence).max() ?? 0
        if role == .canonicalGeneration {
            let changesCommittedState = committedState != first.state
            if changesCommittedState {
                committedState = first.state
                revision &+= 1
            }
        }
        latestCommittedPreparationSequence = max(
            latestCommittedPreparationSequence,
            newestSequence
        )
        receipts.forEach { $0.finish(as: .committed) }
        return true
    }
}

@MainActor
final class PreparedConfigurationPolicyChange {
    enum Phase: Equatable {
        case prepared
        case committed
        case cancelled
    }

    fileprivate weak var ledger: TabConfigurationPolicyLedger?
    fileprivate let state: TabConfigurationPolicyState
    fileprivate let baseRevision: UInt64
    fileprivate let sequence: UInt64
    let expectedSessionGeneration: UInt64
    private(set) var phase: Phase = .prepared

    fileprivate init(
        ledger: TabConfigurationPolicyLedger,
        state: TabConfigurationPolicyState,
        baseRevision: UInt64,
        sequence: UInt64,
        expectedSessionGeneration: UInt64
    ) {
        self.ledger = ledger
        self.state = state
        self.baseRevision = baseRevision
        self.sequence = sequence
        self.expectedSessionGeneration = expectedSessionGeneration
    }

    fileprivate func finish(as phase: Phase) {
        guard self.phase == .prepared else { return }
        self.phase = phase
    }

    func cancel() {
        finish(as: .cancelled)
    }

    func belongs(to policyLedger: TabConfigurationPolicyLedger) -> Bool {
        ledger === policyLedger
    }
}

/// One coherent policy commit for every physical clone in a replacement set.
/// Mixed or partially prepared sets are cancelled instead of reaching the
/// canonical placement transaction.
@MainActor
final class PreparedConfigurationPolicyChangeSet {
    private let policyLedger: TabConfigurationPolicyLedger
    private let receipts: [PreparedConfigurationPolicyChange]
    private let webViews: [WKWebView]
    private(set) var didSettle = false
    let expectedSessionGeneration: UInt64

    init?(
        webViews: [WKWebView],
        policyLedger: TabConfigurationPolicyLedger
    ) {
        guard webViews.isEmpty == false,
              Set(webViews.map(ObjectIdentifier.init)).count
                == webViews.count else {
            Self.cancelPolicyChanges(
                on: webViews,
                belongingTo: policyLedger
            )
            return nil
        }
        let receipts = webViews.compactMap(
            \.sumiPreparedConfigurationPolicyChange
        )
        guard receipts.isEmpty == false else { return nil }
        guard receipts.count == webViews.count else {
            Self.cancelPolicyChanges(
                on: webViews,
                belongingTo: policyLedger
            )
            return nil
        }
        guard let first = receipts.first,
              first.ledger === policyLedger else { return nil }
        guard Set(receipts.map(ObjectIdentifier.init)).count
                == receipts.count,
              receipts.allSatisfy({
                  $0.ledger === policyLedger
                      && $0.phase == .prepared
                      && $0.state == first.state
                      && $0.expectedSessionGeneration
                          == first.expectedSessionGeneration
              }) else {
            Self.cancelPolicyChanges(
                on: webViews,
                belongingTo: policyLedger
            )
            return nil
        }
        self.policyLedger = policyLedger
        self.receipts = receipts
        self.webViews = webViews
        expectedSessionGeneration = first.expectedSessionGeneration
    }

    @discardableResult
    func canCommit(as role: TabConfigurationPolicyLedger.CommitRole) -> Bool {
        canCommit(for: webViews, as: role)
    }

    func canCommit(
        for candidateWebViews: [WKWebView],
        as role: TabConfigurationPolicyLedger.CommitRole
    ) -> Bool {
        guard didSettle == false,
              matchesExactly(candidateWebViews),
              zip(webViews, receipts).allSatisfy({ webView, receipt in
                  webView.sumiPreparedConfigurationPolicyChange
                    === receipt
              }) else {
            return false
        }
        return policyLedger.canCommit(receipts, as: role)
    }

    @discardableResult
    func commit(as role: TabConfigurationPolicyLedger.CommitRole) -> Bool {
        guard didSettle == false else { return false }
        guard canCommit(as: role) else {
            didSettle = true
            receipts.forEach { $0.cancel() }
            clearAssociations()
            return false
        }
        didSettle = true
        let didCommit = policyLedger.commit(receipts, as: role)
        clearAssociations()
        return didCommit
    }

    func belongs(to policyLedger: TabConfigurationPolicyLedger) -> Bool {
        self.policyLedger === policyLedger
    }

    func matchesExactly(_ candidateWebViews: [WKWebView]) -> Bool {
        guard candidateWebViews.count == webViews.count else { return false }
        return Set(candidateWebViews.map(ObjectIdentifier.init))
            == Set(webViews.map(ObjectIdentifier.init))
    }

    var profileID: UUID? {
        receipts.first?.state.profileID
    }

    func cancel() {
        guard didSettle == false else { return }
        didSettle = true
        receipts.forEach { $0.cancel() }
        clearAssociations()
    }

    private func clearAssociations() {
        for (webView, receipt) in zip(webViews, receipts)
            where webView.sumiPreparedConfigurationPolicyChange
                === receipt {
            webView.sumiPreparedConfigurationPolicyChange = nil
        }
    }

    private static func cancelPolicyChanges(
        on webViews: [WKWebView],
        belongingTo policyLedger: TabConfigurationPolicyLedger
    ) {
        for webView in webViews {
            guard let receipt = webView
                .sumiPreparedConfigurationPolicyChange,
                  receipt.ledger === policyLedger else {
                continue
            }
            receipt.cancel()
            webView.sumiPreparedConfigurationPolicyChange = nil
        }
    }
}

private enum TabConfigurationPolicyAssociatedKeys {
    private static let preparedChangeStorage = StaticString(
        "Sumi.TabConfigurationPolicy.preparedChange"
    )

    static var preparedChange: UnsafeRawPointer {
        UnsafeRawPointer(preparedChangeStorage.utf8Start)
    }
}

@MainActor
extension WKWebView {
    var sumiPreparedConfigurationPolicyChange:
        PreparedConfigurationPolicyChange? {
        get {
            objc_getAssociatedObject(
                self,
                TabConfigurationPolicyAssociatedKeys.preparedChange
            ) as? PreparedConfigurationPolicyChange
        }
        set {
            objc_setAssociatedObject(
                self,
                TabConfigurationPolicyAssociatedKeys.preparedChange,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
