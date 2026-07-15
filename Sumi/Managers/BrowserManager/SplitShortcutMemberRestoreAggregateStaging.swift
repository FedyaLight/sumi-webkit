@MainActor
enum SplitShortcutMemberRestoreAggregateStaging {
    struct Failure: Error {
        enum Disposition { case terminal, retained, conflicted }

        let disposition: Disposition
        let settlement: PreparedSplitShortcutMemberRestoreSettlement?
        let cause: any Error
    }

    static func stage(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        participants: SplitShortcutMemberRestoreParticipants,
        structuralMutations: TabStructuralCollectionMutationOwner
    ) throws -> PreparedSplitShortcutMemberRestoreSettlement {
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
        let settlement = PreparedSplitShortcutMemberRestoreSettlement(
            binding: binding, participants: participants, structural: structural
        )
        switch participants.stage() {
        case .staged: break
        case .cleanupRetained:
            let settled = settlement.settleTerminalDrain()
            throw Failure(
                disposition: settled ? .terminal : .conflicted,
                settlement: settlement,
                cause: SplitShortcutMemberRestoreAggregateError
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
                cause: SplitShortcutMemberRestoreAggregateError
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
        _ settlement: PreparedSplitShortcutMemberRestoreSettlement
    ) -> Failure {
        failure(
            restored: settlement.failBindingStage(), settlement: settlement
        )
    }

    private static func failure(
        restored: Bool,
        settlement: PreparedSplitShortcutMemberRestoreSettlement? = nil
    ) -> Failure {
        Failure(
            disposition: restored ? .terminal : .conflicted,
            settlement: settlement,
            cause: restored ? SplitShortcutMemberRestoreAggregateError.stale
                : SplitShortcutMemberRestoreAggregateError.compensationFailed
        )
    }
}
