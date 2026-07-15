@MainActor
final class PreparedTabStructuralCollectionAggregate {
    private enum State { case open, staged, terminal }

    private let owner: TabStructuralCollectionMutationOwner
    private let transaction: TabStructuralMutationTransaction
    private var target: TabStructuralMutationTransaction.Snapshot?
    private var state = State.open

    init(
        owner: TabStructuralCollectionMutationOwner,
        transaction: TabStructuralMutationTransaction
    ) {
        self.owner = owner
        self.transaction = transaction
    }

    func stage() -> Bool {
        guard case .open = state,
              let target = owner.seal(transaction) else { return false }
        self.target = target
        state = .staged
        return true
    }

    func canStage() -> Bool {
        guard case .open = state else { return false }
        return owner.ownsOpen(transaction)
    }

    func isCurrent() -> Bool {
        guard case .staged = state, let target else { return false }
        return owner.currentSnapshotMatches(target)
    }

    @discardableResult
    func publish() -> Bool {
        guard isCurrent() else { return false }
        state = .terminal
        owner.apply(transaction.finish(committed: true))
        return true
    }

    @discardableResult
    func rollback() -> Bool {
        switch state {
        case .open:
            guard owner.releaseOpen(transaction) else { return false }
            if transaction.hasRecordedMutations == false {
                transaction.discardUnmodified()
                state = .terminal
                return true
            }
        case .staged:
            guard isCurrent() else { return false }
        case .terminal:
            return false
        }
        state = .terminal
        owner.apply(transaction.finish(committed: false))
        return true
    }

    func abandonForTerminalDrain() {
        precondition(canAbandonForTerminalDrain())
        state = .terminal
    }

    func canAbandonForTerminalDrain() -> Bool { isCurrent() }
}

extension TabStructuralCollectionMutationOwner {
    typealias PreparedAggregate = PreparedTabStructuralCollectionAggregate
}
