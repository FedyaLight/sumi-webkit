@MainActor
enum ShortcutSplitLauncherMoveCompensation {
    static func settleFailedPreparation(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        structural: TabStructuralCollectionMutationOwner.PreparedAggregate
    ) -> Bool {
        let bindingRestored = binding.cancelPrepared()
        let structuralRestored = structural.rollback()
        return bindingRestored && structuralRestored
    }

    static func settleFailedBindingStage(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        participants: ShortcutSplitLauncherMoveParticipants,
        structural: TabStructuralCollectionMutationOwner.PreparedAggregate
    ) -> Bool {
        let participantsRestored = participants.rollbackModel()
        let structuralRestored = structural.rollback()
        let bindingRestored = binding.confirmStructuralRollback()
        return participantsRestored && structuralRestored && bindingRestored
    }

    static func rollbackStagedModel(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        participants: ShortcutSplitLauncherMoveParticipants,
        structural: TabStructuralCollectionMutationOwner.PreparedAggregate
    ) -> Bool {
        var restored = true
        do { try binding.rollbackBinding() } catch { restored = false }
        if participants.rollbackModel() == false { restored = false }
        if structural.rollback() == false { restored = false }
        if binding.confirmStructuralRollback() == false { restored = false }
        return restored
    }
}

enum ShortcutSplitLauncherMoveAggregateError: Error {
    case stale, compensationFailed
}
