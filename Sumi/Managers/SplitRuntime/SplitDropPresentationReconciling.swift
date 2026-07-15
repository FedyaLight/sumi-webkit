@MainActor
protocol SplitDropPresentationReconciling: AnyObject {
    func reconcile(_ effect: SplitDropCommitEffect)
}

extension WindowSplitPresentationSynchronizer: SplitDropPresentationReconciling {
    func reconcile(_ effect: SplitDropCommitEffect) {
        synchronize(
            previousGroups: effect.previousGroups,
            affectedGroupIDs: effect.affectedGroupIDs,
            preferredSelections: [
                effect.callerWindowID: WindowSplitSelection(
                    groupID: effect.targetGroupID,
                    activeMemberID: effect.preferredActiveMemberID
                ),
            ]
        )
    }
}
