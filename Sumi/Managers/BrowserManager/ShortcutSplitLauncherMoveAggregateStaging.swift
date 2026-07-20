@MainActor
enum ShortcutSplitLauncherMoveAggregateStaging {
    struct Failure: Error {
        enum Disposition { case terminal, retained, conflicted }

        let disposition: Disposition
        let settlement: PreparedShortcutSplitLauncherMoveSettlement?
        let cause: any Error
    }

    static func stage(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        participants: ShortcutSplitLauncherMoveParticipants,
        structuralMutations: TabStructuralCollectionMutationOwner
    ) throws -> PreparedShortcutSplitLauncherMoveSettlement {
        guard binding.validateForStaging() else {
            let bindingCancelled = binding.cancelPrepared()
            let participantsCancelled = participants.cancelPrepared()
            throw failure(restored: bindingCancelled && participantsCancelled)
        }
        guard let structural = structuralMutations.prepareAggregate() else {
            let bindingCancelled = binding.cancelPrepared()
            let participantsCancelled = participants.cancelPrepared()
            throw failure(restored: bindingCancelled && participantsCancelled)
        }
        let settlement = PreparedShortcutSplitLauncherMoveSettlement(
            binding: binding, participants: participants, structural: structural
        )
        switch participants.stage() {
        case .staged: break
        case .cleanupRetained:
            let settled = settlement.settleTerminalDrain()
            throw Failure(
                disposition: settled ? .terminal : .conflicted,
                settlement: settlement,
                cause: ShortcutSplitLauncherMoveAggregateError
                    .compensationFailed
            )
        case .restored:
            throw failure(
                restored: settlement.failPreparation(), settlement: settlement
            )
        case .conflicted:
            settlement.failParticipantStage()
            throw Failure(
                disposition: .conflicted,
                settlement: settlement,
                cause: ShortcutSplitLauncherMoveAggregateError
                    .compensationFailed
            )
        }
        guard binding.stageCatalog() else {
            throw failedBindingStage(settlement)
        }
        do { try binding.stageBinding() } catch {
            if binding.retainsModelAfterFailedStage() {
                guard settlement.structuralStage(),
                      participants.acceptWindowModel(),
                      binding.canSettleTerminalDrain(),
                      participants.stagedModelIsExact() else {
                    throw Failure(
                        disposition: .conflicted,
                        settlement: settlement,
                        cause: error
                    )
                }
                throw Failure(
                    disposition: .retained,
                    settlement: settlement,
                    cause: error
                )
            }
            throw failedBindingStage(settlement)
        }
        guard settlement.structuralStage() else {
            let restored = settlement.rollbackStagedModel()
            throw failure(restored: restored, settlement: settlement)
        }
        guard participants.acceptWindowModel() else {
            let restored = settlement.rollbackStagedModel()
            throw failure(restored: restored, settlement: settlement)
        }
        guard binding.stagedModelIsExact(),
              participants.stagedModelIsExact(),
              settlement.isCurrent() else {
            let restored = settlement.rollbackStagedModel()
            throw failure(restored: restored, settlement: settlement)
        }
        return settlement
    }

    private static func failedBindingStage(
        _ settlement: PreparedShortcutSplitLauncherMoveSettlement
    ) -> Failure {
        failure(
            restored: settlement.failBindingStage(), settlement: settlement
        )
    }

    private static func failure(
        restored: Bool,
        settlement: PreparedShortcutSplitLauncherMoveSettlement? = nil
    ) -> Failure {
        Failure(
            disposition: restored ? .terminal : .conflicted,
            settlement: settlement,
            cause: restored ? ShortcutSplitLauncherMoveAggregateError.stale
                : ShortcutSplitLauncherMoveAggregateError.compensationFailed
        )
    }
}
