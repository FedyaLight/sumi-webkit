import Foundation
@MainActor
enum DisplayedTabShortcutWindowTransition {
    static func apply(
        to state: inout BrowserWindowShortcutMutationState,
        originalTabId: UUID,
        splitTransition: RegularTabShortcutWindowTransitionPlan,
        liveTab: Tab?,
        sourceSpaceId: UUID?,
        isSelected: Bool,
        regularTabs: RegularTabCollectionOwner
    ) -> Bool {
        let previousSessionState = ShortcutConversionWindowSessionState(state)
        let selectedSourceGroupID = splitTransition.sourceGroupID.flatMap { groupId in
            state.splitSelection?.groupID == groupId
                && state.splitSelection?.activeMemberID == .regularTab(originalTabId)
                ? groupId
                : nil
        }
        if isSelected || selectedSourceGroupID != nil, let liveTab {
            _ = WindowTabSelectionStateApplicator.apply(
                liveTab,
                to: &state,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        }
        if let groupID = splitTransition.selectedTargetGroupID(
            isSelected: isSelected,
            selectedSourceGroupID: selectedSourceGroupID
        ) {
            state.splitSelection = WindowSplitSelection(
                groupID: groupID,
                activeMemberID: splitTransition.replacementMemberID
            )
        }
        if let sourceSpaceId,
           state.activeTabForSpace[sourceSpaceId] == originalTabId {
            state.activeTabForSpace[sourceSpaceId] = regularTabs
                .tabs(in: sourceSpaceId).first?.id
        }
        state.selectionHistory.removeFromRegularTabHistory(originalTabId)
        return previousSessionState != ShortcutConversionWindowSessionState(state)
    }
}
