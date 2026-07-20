@MainActor
enum ShortcutSplitLauncherMoveCommitPublisher {
    static func publish(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        participants: ShortcutSplitLauncherMoveParticipants,
        settlement: PreparedShortcutSplitLauncherMoveSettlement,
        structuralLookup: TabStructuralLookupCoordinator,
        markTerminal: () -> Void
    ) {
        structuralLookup.withTransaction {
            binding.publishModelCommit {
                precondition(
                    participants.commitSilentModelAndClaimTerminalEffects()
                )
                markTerminal()
                precondition(settlement.publishStructural())
                participants.publishObservableModel()
            }
        }
        binding.publishTerminalEffects()
        participants.publishTerminalEffects()
    }
}
