import Foundation

/// Exact, observation-silent residence half of one presentation refresh.
/// Every caller shares this staging/validation/rollback implementation, so a
/// launcher move and an ordinary binding refresh cannot drift semantically.
@MainActor
final class LiveShortcutPresentationResidenceTransaction {
    private enum State { case staged, published, rolledBack, discarded }

    private let pin: ShortcutPin
    private let admission: LiveShortcutPresentationRefreshAdmission
    private let staging: LiveShortcutResidenceMutationStaging
    private let changes: [LiveShortcutResidenceMutationStaging.Change]
    private var state = State.staged

    init(
        pin: ShortcutPin,
        admission: LiveShortcutPresentationRefreshAdmission,
        staging: LiveShortcutResidenceMutationStaging,
        changes: [LiveShortcutResidenceMutationStaging.Change]
    ) {
        self.pin = pin
        self.admission = admission
        self.staging = staging
        self.changes = changes
    }

    func isCurrent() -> Bool {
        guard case .staged = state else { return false }
        return admission.accepts(pin) && staging.canPublish(changes)
    }

    func canRollback() -> Bool {
        guard case .staged = state else { return false }
        return staging.canPublish(changes)
    }

    @discardableResult
    func rollback() -> Bool {
        guard canRollback(), staging.rollback(changes) else { return false }
        state = .rolledBack
        return true
    }

    @discardableResult
    func publish() -> Bool {
        guard isCurrent() else { return false }
        state = .published
        if changes.isEmpty == false {
            staging.publish(changes)
        }
        return true
    }

    /// An enclosing aggregate transaction restored the complete residence
    /// snapshot, so per-change compensation must never run afterward.
    func discardAfterAggregateRollback() {
        guard case .staged = state else {
            preconditionFailure("Residence transaction was already settled")
        }
        state = .discarded
    }
}
