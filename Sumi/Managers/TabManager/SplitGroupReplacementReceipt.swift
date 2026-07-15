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

    func rollbackModel() {
        guard case .committed = state else { return }
        store.replaceAll(with: plan.expected)
        state = .prepared
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
