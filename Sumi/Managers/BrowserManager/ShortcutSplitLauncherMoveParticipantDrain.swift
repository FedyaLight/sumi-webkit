@MainActor
enum ShortcutSplitLauncherMoveParticipantState {
    case prepared, staged, claimed, restoredAfterFailedClaim
    case retainedCleanupConflict
    case terminalEffectsClaimed, conflicted, terminal
}

@MainActor
enum ShortcutSplitLauncherMoveParticipantDrain {
    static func canSettle(
        state: ShortcutSplitLauncherMoveParticipantState,
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt
    ) -> Bool {
        switch state {
        case .claimed, .retainedCleanupConflict:
            return presentation.canForfeitPreservingCurrent()
                && (retirement?.canAbandonForTerminalDrain() ?? true)
                && topology.canForfeitPreservingCurrent()
        case .restoredAfterFailedClaim:
            return presentation.aggregateWindowModelIsExact()
                && topology.committedModelIsExact()
        case .prepared, .staged, .terminalEffectsClaimed, .conflicted,
                .terminal:
            return false
        }
    }

    static func prepare(
        state: inout ShortcutSplitLauncherMoveParticipantState,
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt
    ) -> ShortcutLiveTerminalDrainEffect? {
        guard canSettle(
            state: state,
            presentation: presentation,
            retirement: retirement,
            topology: topology
        ) else { return nil }
        if case .restoredAfterFailedClaim = state {
            presentation.rollback()
            guard topology.rollbackModel() else { return nil }
            topology.rollback()
            state = .terminal
            return {}
        }
        if presentation.canAbandonForTerminalDrain() {
            presentation.abandonForTerminalDrain()
        } else {
            presentation.forfeitPreservingCurrent()
        }
        if topology.canAbandonForTerminalDrain() {
            topology.abandonForTerminalDrain()
        } else {
            topology.forfeitPreservingCurrent()
        }
        let effect: ShortcutLiveTerminalDrainEffect
        if let retirement {
            effect = retirement.finishTerminalDrain()
        } else {
            effect = {}
        }
        state = .terminal
        return effect
    }
}
