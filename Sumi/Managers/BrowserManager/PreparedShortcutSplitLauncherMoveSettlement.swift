@MainActor
final class PreparedShortcutSplitLauncherMoveSettlement {
    private enum State { case active, rolledBack, terminal, conflicted }

    private let binding: any ShortcutSplitLauncherBindingModelTransaction
    private let participants: ShortcutSplitLauncherMoveParticipants
    private let structural: TabStructuralCollectionMutationOwner.PreparedAggregate
    private var state = State.active

    init(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        participants: ShortcutSplitLauncherMoveParticipants,
        structural: TabStructuralCollectionMutationOwner.PreparedAggregate
    ) {
        self.binding = binding
        self.participants = participants
        self.structural = structural
    }

    func structuralStage() -> Bool {
        guard case .active = state else { return false }
        return structural.stage()
    }

    func isCurrent() -> Bool {
        guard case .active = state else { return false }
        return structural.isCurrent()
    }

    func publishStructural() -> Bool {
        guard case .active = state else { return false }
        state = .terminal
        return structural.publish()
    }

    func failPreparation() -> Bool {
        guard case .active = state else { return false }
        let restored = ShortcutSplitLauncherMoveCompensation
            .settleFailedPreparation(binding: binding, structural: structural)
        state = restored ? .terminal : .conflicted
        return restored
    }

    func failParticipantStage() {
        guard case .active = state else { return }
        _ = binding.cancelPrepared()
        _ = structural.rollback()
        state = .conflicted
    }

    func failBindingStage() -> Bool {
        guard case .active = state else { return false }
        let restored = ShortcutSplitLauncherMoveCompensation
            .settleFailedBindingStage(
                binding: binding,
                participants: participants,
                structural: structural
            )
        state = restored ? .terminal : .conflicted
        return restored
    }

    func rollbackStagedModel() -> Bool {
        guard case .active = state else { return false }
        let restored = ShortcutSplitLauncherMoveCompensation
            .rollbackStagedModel(
                binding: binding,
                participants: participants,
                structural: structural
            )
        state = restored ? .rolledBack : .conflicted
        return restored
    }

    func publishRollback() {
        guard case .rolledBack = state else { return }
        state = .terminal
        binding.publishRollback()
    }

    func canSettleTerminalDrain() -> Bool {
        guard case .active = state else {
            switch state {
            case .rolledBack, .terminal: return true
            case .active, .conflicted: return false
            }
        }
        return participants.canSettleTerminalDrain()
            && binding.canSettleTerminalDrain()
            && structural.canAbandonForTerminalDrain()
    }

    func settleTerminalDrain() -> Bool {
        if case .terminal = state { return true }
        if case .rolledBack = state {
            guard binding.settleTerminalDrain() else { return false }
            state = .terminal
            return true
        }
        guard canSettleTerminalDrain(),
              let destructiveEffect = participants.prepareTerminalDrain()
        else { return false }
        state = .terminal
        let siblingsSettled = ShortcutSplitLauncherMoveTerminalDrain
            .settleSiblings(binding: binding, structural: structural)
        destructiveEffect()
        return siblingsSettled
    }
}
