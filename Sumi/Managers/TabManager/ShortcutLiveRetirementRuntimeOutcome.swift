enum ShortcutLiveRetirementModelCompensation: Equatable {
    case restored, retainedConflict
}

enum ShortcutLiveRetirementRuntimeStageOutcome {
    case staged
    case rejected(ShortcutLiveRetirementModelCompensation)
    case cleanup(
        CommittedTabRuntimeRetirementCleanupOwnership,
        ShortcutLiveRetirementModelCompensation
    )
}

enum ShortcutLiveRetirementRuntimeClaimOutcome {
    case claimed(ShortcutLiveRetirementBatchRuntimeParticipant.ClaimedEffect)
    case rejected(ShortcutLiveRetirementModelCompensation)
    case cleanup(
        CommittedTabRuntimeRetirementCleanupOwnership,
        ShortcutLiveRetirementModelCompensation
    )
}

extension ShortcutLiveRetirementBatchModelParticipant {
    func compensateBeforeRuntimeCommit()
        -> ShortcutLiveRetirementModelCompensation {
        cancelBeforeRuntimeCommit() ? .restored : .retainedConflict
    }
}
