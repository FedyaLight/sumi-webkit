import Foundation
import SumiDomain

/// Prepares and executes the window-local settlement paired with one shortcut
/// member restoration. The topology coordinator remains outside this role.
@MainActor
final class SplitShortcutMemberRestorePublication {
    private let presentations: WindowSplitPresentationSynchronizer
    private let folderOpenState: TabFolderOpenStateService
    private let visuals: BrowserWindowVisualCoordinator

    init(
        presentations: WindowSplitPresentationSynchronizer,
        folderOpenState: TabFolderOpenStateService,
        visuals: BrowserWindowVisualCoordinator
    ) {
        self.presentations = presentations
        self.folderOpenState = folderOpenState
        self.visuals = visuals
    }

    func prepare(
        _ prepared: SplitShortcutMemberRestorePreparation,
        memberID: SplitMemberID,
        sourceGroup: SumiDomain.SplitGroup,
        windowState: BrowserWindowState,
        preserveLiveInstance: Bool
    ) -> PreparedWindowSplitPresentationSettlement? {
        let targetPresentsGroup = windowState.splitSelection?.groupID
            == sourceGroup.id
        let settlesTargetWindow = preserveLiveInstance || targetPresentsGroup
        let terminalParticipants: WindowSplitPresentationTerminalParticipants =
            settlesTargetWindow
                ? [SplitShortcutMemberRestoreHandoffReceipt(
                    window: windowState,
                    visuals: visuals
                )]
                : []
        return presentations.prepareSettlementAgainstSource(
            previousGroups: [sourceGroup],
            sourceGroups: prepared.sourceGroups,
            replacementGroups: prepared.replacementGroups,
            affectedGroupIDs: [sourceGroup.id],
            standaloneMembers: preserveLiveInstance
                ? [windowState.id: memberID] : [:],
            unavailableMembers: preserveLiveInstance || !targetPresentsGroup
                ? [:] : [windowState.id: [memberID]],
            requiredWindows: settlesTargetWindow
                ? [windowState.id: windowState] : [:],
            terminalParticipants: terminalParticipants,
            sessionWriteUrgency: .immediate
        )
    }

    func execute(
        _ move: any ShortcutSplitLauncherComposedMoveBatchParticipant,
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt,
        retirementService: ShortcutLiveTabRetirementService
    ) -> PreparedProfileAssignmentBatchTransitionOutcome? {
        move.executeRestore(
            presentation: presentation,
            retirement: retirement,
            topology: topology,
            retirementService: retirementService,
            folderOpenState: folderOpenState
        )
    }
}
