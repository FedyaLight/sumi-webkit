@MainActor
final class ShortcutLiveRetirementSplitParticipant {
    private enum State { case prepared, staged, terminal }

    private let receipt: SplitGroupReplacementReceipt?
    private var state = State.prepared

    init(receipt: SplitGroupReplacementReceipt?) {
        self.receipt = receipt
    }

    func isCurrent() -> Bool {
        switch state {
        case .prepared: return receipt?.isCurrent() ?? true
        case .staged: return receipt?.committedModelIsExact() ?? true
        case .terminal: return false
        }
    }

    func stage() -> Bool {
        guard case .prepared = state,
              receipt?.commitModel() != false else { return false }
        state = .staged
        return isCurrent()
    }

    func rollback() -> Bool {
        guard case .staged = state,
              receipt?.rollbackModel() != false else { return false }
        state = .prepared
        return isCurrent()
    }

    func publish() {
        guard case .staged = state else {
            preconditionFailure("Split retirement topology was not staged")
        }
        state = .terminal
        receipt?.publish()
    }

    func forfeitToForeignMutation() -> Bool {
        guard case .staged = state,
              receipt?.forfeitToForeignMutation() != false else {
            return false
        }
        state = .terminal
        return true
    }

    func cancelPrepared() {
        guard case .prepared = state else { return }
        state = .terminal
        receipt?.rollback()
    }
}
