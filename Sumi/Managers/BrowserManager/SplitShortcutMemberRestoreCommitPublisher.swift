@MainActor
enum SplitShortcutMemberRestoreCommitPublisher {
    static func publish(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        participants: SplitShortcutMemberRestoreParticipants,
        settlement: PreparedSplitShortcutMemberRestoreSettlement,
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
