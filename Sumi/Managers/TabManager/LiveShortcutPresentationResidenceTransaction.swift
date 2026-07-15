import Foundation

/// Exact, observation-silent residence half of one presentation refresh.
/// Every caller shares this staging/validation/rollback implementation, so a
/// launcher move and an ordinary binding refresh cannot drift semantically.
@MainActor
final class LiveShortcutPresentationResidenceTransaction {
    private enum State {
        case prepared
        case staged([LiveShortcutResidenceMutationStaging.Change])
        case published
        case rolledBack
        case discarded
    }

    private let pin: ShortcutPin
    private let admission: LiveShortcutPresentationRefreshAdmission
    private let staging: LiveShortcutResidenceMutationStaging
    private let plans: [LiveShortcutResidenceMutationStaging.Plan]
    private var state = State.prepared

    init(
        pin: ShortcutPin,
        admission: LiveShortcutPresentationRefreshAdmission,
        staging: LiveShortcutResidenceMutationStaging,
        plans: [LiveShortcutResidenceMutationStaging.Plan]
    ) {
        self.pin = pin
        self.admission = admission
        self.staging = staging
        self.plans = plans
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return admission.accepts(pin) && staging.canStage(plans)
    }

    func stage() -> Bool {
        guard validateForStaging(), let changes = staging.stage(plans) else {
            return false
        }
        state = .staged(changes)
        guard stagedModelIsExact() else {
            precondition(rollback())
            return false
        }
        return true
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged(let changes) = state else { return false }
        return admission.accepts(pin) && staging.canPublish(changes)
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        state = .rolledBack
        return true
    }

    func canRollback() -> Bool {
        guard case .staged(let changes) = state else { return false }
        return staging.canPublish(changes)
    }

    @discardableResult
    func rollback() -> Bool {
        guard case .staged(let changes) = state,
              canRollback(), staging.rollback(changes) else { return false }
        state = .rolledBack
        return true
    }

    @discardableResult
    func publish() -> Bool {
        guard case .staged(let changes) = state,
              stagedModelIsExact() else { return false }
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

    func canAbandonForTerminalDrain() -> Bool { stagedModelIsExact() }

    func abandonForTerminalDrain() {
        precondition(canAbandonForTerminalDrain())
        state = .discarded
    }
}
