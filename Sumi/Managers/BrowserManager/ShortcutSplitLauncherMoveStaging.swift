@MainActor
enum ShortcutSplitLauncherMoveStaging {
    static func stage(
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt
    ) -> ShortcutSplitLauncherMoveParticipants.StageOutcome {
        guard topology.commitModel() else {
            return settlePreparedFailure(
                presentation: presentation,
                retirement: retirement,
                topology: topology
            )
        }
        guard presentation.stage() else {
            let presentationRestored = presentation.settleAfterFailedStage()
            let topologyRestored = topology.rollbackModel()
            topology.rollback()
            return outcome(restored: presentationRestored && topologyRestored)
        }
        switch retirement?.begin() ?? .staged {
        case .staged:
            break
        case .cleanupRetained:
            return .cleanupRetained
        case .restored, .conflicted:
            presentation.rollback()
            let retirementRestored = retirement?.settleAfterFailedBegin() ?? true
            let topologyRestored = topology.rollbackModel()
            topology.rollback()
            return outcome(restored: retirementRestored && topologyRestored)
        }
        return .staged
    }

    private static func settlePreparedFailure(
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt
    ) -> ShortcutSplitLauncherMoveParticipants.StageOutcome {
        outcome(
            restored: ShortcutSplitLauncherMoveParticipantCompensation
                .cancelPrepared(
                    presentation: presentation,
                    retirement: retirement,
                    topology: topology
                )
        )
    }

    private static func outcome(
        restored: Bool
    ) -> ShortcutSplitLauncherMoveParticipants.StageOutcome {
        restored ? .restored : .conflicted
    }
}
