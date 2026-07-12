import Foundation
import SumiWebRuntime

/// Owns the exact prepare/stage/settle state machine for a Tab profile change.
/// Callers operate on this transaction directly; `Tab` does not mirror its
/// lifecycle API or participate in revision validation.
@MainActor
final class TabProfileAssignmentStateMachine {
    private(set) var currentProfileID: UUID?

    private var revision: UInt64 = 0
    private var pendingIntent: DeferredWebViewProfileAssignmentIntent?
    private var settlingIntent: DeferredWebViewProfileAssignmentIntent?

    /// Monotonic read-only revision for external exact-authority evidence.
    /// Any assignment mutation advances it, so A→B→A churn is observable.
    var changeRevision: UInt64 { revision }

    /// Replaces stable model state outside this transaction. A replacement
    /// tombstones pending evidence; physical settlement cannot be superseded
    /// because its repository lease must finish or roll back first.
    @discardableResult
    func replaceCurrentProfileID(_ profileID: UUID?) -> Bool {
        guard settlingIntent == nil else { return false }
        guard currentProfileID != profileID || pendingIntent != nil else {
            return true
        }
        advanceRevision()
        pendingIntent = nil
        currentProfileID = profileID
        return true
    }

    func begin(
        desiredProfileID: UUID?,
        resolvedProfileID: UUID,
        targetURL: URL,
        requiresStructuralPersistence: Bool
    ) -> DeferredWebViewProfileAssignmentIntent {
        precondition(
            settlingIntent == nil,
            "A profile transition must settle before another transition begins"
        )
        advanceRevision()
        let intent = DeferredWebViewProfileAssignmentIntent(
            revision: revision,
            expectedProfileID: currentProfileID,
            desiredProfileID: desiredProfileID,
            resolvedProfileID: resolvedProfileID,
            targetURL: targetURL,
            requiresStructuralPersistence: requiresStructuralPersistence
        )
        pendingIntent = intent
        return intent
    }

    func isCurrent(_ intent: DeferredWebViewProfileAssignmentIntent) -> Bool {
        pendingIntent == intent
            && revision == intent.revision
            && currentProfileID == intent.expectedProfileID
    }

    func hasPendingAssignment(to desiredProfileID: UUID?) -> Bool {
        let intent = pendingIntent ?? settlingIntent
        return intent?.desiredProfileID == desiredProfileID
    }

    var hasUnsettledAssignment: Bool {
        pendingIntent != nil || settlingIntent != nil
    }

    var hasStagedSettlement: Bool {
        settlingIntent != nil
    }

    @discardableResult
    func cancelPending() -> Bool {
        guard pendingIntent != nil else { return false }
        pendingIntent = nil
        return true
    }

    @discardableResult
    func commit(_ intent: DeferredWebViewProfileAssignmentIntent) -> Bool {
        guard isCurrent(intent) else { return false }
        currentProfileID = intent.desiredProfileID
        pendingIntent = nil
        return true
    }

    /// Applies the model half while retaining the exact intent until physical
    /// WebView replacement and the repository retirement lease settle.
    @discardableResult
    func stage(_ intent: DeferredWebViewProfileAssignmentIntent) -> Bool {
        guard settlingIntent == nil, isCurrent(intent) else { return false }
        currentProfileID = intent.desiredProfileID
        pendingIntent = nil
        settlingIntent = intent
        return true
    }

    func isCurrentStaged(
        _ intent: DeferredWebViewProfileAssignmentIntent
    ) -> Bool {
        settlingIntent == intent
            && revision == intent.revision
            && currentProfileID == intent.desiredProfileID
    }

    @discardableResult
    func finish(_ intent: DeferredWebViewProfileAssignmentIntent) -> Bool {
        guard isCurrentStaged(intent) else { return false }
        settlingIntent = nil
        return true
    }

    @discardableResult
    func rollback(_ intent: DeferredWebViewProfileAssignmentIntent) -> Bool {
        guard isCurrentStaged(intent) else { return false }
        currentProfileID = intent.expectedProfileID
        settlingIntent = nil
        return true
    }

    func abort(_ intent: DeferredWebViewProfileAssignmentIntent) {
        guard pendingIntent == intent else { return }
        pendingIntent = nil
    }

    private func advanceRevision() {
        precondition(revision < UInt64.max, "Tab profile-assignment revision exhausted")
        revision += 1
    }
}
