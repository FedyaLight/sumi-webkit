import Foundation
@MainActor
enum DisplayedTabShortcutWindowTransition {
    static func apply(
        to windowState: BrowserWindowState,
        originalTabId: UUID,
        splitTransition: RegularTabShortcutWindowTransitionPlan,
        liveTab: Tab?,
        sourceSpaceId: UUID?,
        isSelected: Bool,
        regularTabs: RegularTabCollectionOwner
    ) -> Bool {
        let previousSessionState = ShortcutConversionWindowSessionState(windowState)
        let selectedSourceGroupID = splitTransition.sourceGroupID.flatMap { groupId in
            windowState.splitSelection?.groupID == groupId
                && windowState.splitSelection?.activeMemberID == .regularTab(originalTabId)
                ? groupId
                : nil
        }
        if (isSelected || selectedSourceGroupID != nil), let liveTab {
            _ = WindowTabSelectionStateApplicator.apply(
                liveTab,
                to: windowState,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        }
        if let groupID = splitTransition.selectedTargetGroupID(
            isSelected: isSelected,
            selectedSourceGroupID: selectedSourceGroupID
        ) {
            windowState.splitSelection = WindowSplitSelection(
                groupID: groupID,
                activeMemberID: splitTransition.replacementMemberID
            )
        }
        if let sourceSpaceId,
           windowState.activeTabForSpace[sourceSpaceId] == originalTabId {
            windowState.activeTabForSpace[sourceSpaceId] = regularTabs
                .tabs(in: sourceSpaceId).first?.id
        }
        windowState.selectionHistory.removeFromRegularTabHistory(originalTabId)
        return previousSessionState != ShortcutConversionWindowSessionState(windowState)
    }
}
