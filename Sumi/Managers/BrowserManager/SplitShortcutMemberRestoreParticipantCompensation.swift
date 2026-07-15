@MainActor
enum SplitShortcutMemberRestoreParticipantCompensation {
    static func cancelPrepared(
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt
    ) -> Bool {
        let presentationCancelled = presentation.cancelPrepared()
        let retirementCancelled = retirement?.cancelPrepared() ?? true
        topology.rollback()
        return presentationCancelled && retirementCancelled
    }

    static func rollbackStaged(
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt
    ) -> Bool {
        var restored = retirement?.rollback() ?? true
        presentation.rollback()
        let topologyRestored = topology.rollbackModel() && topology.isCurrent()
        topology.rollback()
        if topologyRestored == false { restored = false }
        return restored
    }
}
