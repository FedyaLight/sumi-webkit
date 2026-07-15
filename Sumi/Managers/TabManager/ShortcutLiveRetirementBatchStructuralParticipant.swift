@MainActor
final class ShortcutLiveRetirementBatchStructuralParticipant {
    private enum State { case prepared, staged, terminal }

    private let windows: BrowserWindowShortcutMutationOwner.PreparedAggregate
    private let topology: ShortcutLiveRetirementSplitParticipant
    private var state = State.prepared

    init?(
        plan: ShortcutLiveRetirementBatchPlan,
        windowMutations: BrowserWindowShortcutMutationOwner
    ) {
        topology = ShortcutLiveRetirementSplitParticipant(
            receipt: plan.splitTopology
        )
        guard let windows = windowMutations.prepareAggregate({
            plan.windows.allSatisfy { entry in
                entry.isCurrent(using: plan.attachment)
                    && windowMutations.stage(entry.window) {
                        $0 = entry.target
                    }
            }
        }) else { return nil }
        self.windows = windows
    }

    func isCurrent() -> Bool {
        switch state {
        case .prepared:
            return windows.isCurrent() && topology.isCurrent()
        case .staged:
            return windows.isCurrent() && topology.isCurrent()
        case .terminal:
            return false
        }
    }

    func stage() -> Bool {
        guard case .prepared = state, isCurrent(), topology.stage() else {
            return false
        }
        guard windows.stage() else {
            precondition(topology.rollback())
            return false
        }
        state = .staged
        return isCurrent()
    }

    func rollback() -> Bool {
        guard case .staged = state else { return false }
        guard topology.rollback() else {
            _ = topology.forfeitToForeignMutation()
            if windows.canAbandonForTerminalDrain() {
                windows.abandonForTerminalDrain()
            }
            state = .terminal
            return false
        }
        let windowsRestored = windows.rollback()
        state = .terminal
        return windowsRestored
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        let windowsCancelled = windows.discardPrepared()
        topology.cancelPrepared()
        state = .terminal
        return windowsCancelled
    }

    func publish() {
        guard case .staged = state, isCurrent() else {
            preconditionFailure("Shortcut structural batch was not staged")
        }
        state = .terminal
        topology.publish()
        windows.publish()
    }
}
