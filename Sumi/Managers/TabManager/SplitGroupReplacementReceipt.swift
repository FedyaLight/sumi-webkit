import SumiDomain

@MainActor
struct SplitGroupReplacementPlan {
    let expected: [SumiDomain.SplitGroup]
    let replacement: [SumiDomain.SplitGroup]
    let persist: Bool
}

/// Exact-once ownership of a validated split-store replacement. Model state
/// remains reversible until the enclosing aggregate publishes its decision.
@MainActor
final class SplitGroupReplacementReceipt {
    private enum State {
        case prepared
        case committed
        case published
        case cancelled
        case abandoned
    }

    private let store: SplitGroupStore
    private let publisher: SplitGroupMutationService
    private let plan: SplitGroupReplacementPlan
    private var state = State.prepared

    init(
        store: SplitGroupStore,
        publisher: SplitGroupMutationService,
        plan: SplitGroupReplacementPlan
    ) {
        self.store = store
        self.publisher = publisher
        self.plan = plan
    }

    func isCurrent() -> Bool {
        guard case .prepared = state else { return false }
        return store.groups == plan.expected
    }

    @discardableResult
    func commitModel() -> Bool {
        guard isCurrent() else { return false }
        commitAdmittedModel()
        return true
    }

    func commitAdmittedModel() {
        guard isCurrent() else {
            preconditionFailure("Split replacement lost admitted authority")
        }
        state = .committed
        store.replaceAll(with: plan.replacement)
    }

    @discardableResult
    func rollbackModel() -> Bool {
        guard committedModelIsExact() else { return false }
        store.replaceAll(with: plan.expected)
        guard store.groups == plan.expected else { return false }
        state = .prepared
        return true
    }

    func committedModelIsExact() -> Bool {
        guard case .committed = state else { return false }
        return store.groups == plan.replacement
    }

    func abandonForTerminalDrain() {
        precondition(canAbandonForTerminalDrain())
        state = .abandoned
    }

    func forfeitToForeignMutation() -> Bool {
        guard case .committed = state,
              store.groups != plan.replacement else { return false }
        state = .abandoned
        return true
    }

    func canAbandonForTerminalDrain() -> Bool { committedModelIsExact() }

    func canForfeitPreservingCurrent() -> Bool {
        if case .committed = state { return true }
        return false
    }

    func forfeitPreservingCurrent() {
        precondition(canForfeitPreservingCurrent())
        state = .abandoned
    }

    func publish() {
        guard case .committed = state else { return }
        state = .published
        publisher.publishPreparedReplacement(plan)
    }

    func rollback() {
        guard case .prepared = state else { return }
        state = .cancelled
    }
}
