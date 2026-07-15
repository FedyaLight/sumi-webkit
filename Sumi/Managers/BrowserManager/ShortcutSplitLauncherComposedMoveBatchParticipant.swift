@MainActor
protocol ShortcutSplitLauncherComposedMoveBatchParticipant: AnyObject {
    func admitPresentationIdentity(
        to presentation: PreparedWindowSplitPresentationSettlement
    ) -> Bool

    func executeRestore(
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt,
        retirementService: ShortcutLiveTabRetirementService,
        folderOpenState: TabFolderOpenStateService
    ) -> PreparedProfileAssignmentBatchTransitionOutcome?
    func cancelPrepared() -> Bool
}
