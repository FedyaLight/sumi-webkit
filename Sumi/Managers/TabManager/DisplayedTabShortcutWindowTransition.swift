import Foundation

@MainActor
enum DisplayedTabShortcutWindowTransition {
    static func apply(
        to state: inout BrowserWindowShortcutMutationState,
        originalTabId: UUID,
        splitTransition: RegularTabShortcutWindowTransitionPlan,
        terminalSelection: DisplayedTabShortcutTerminalSelectionPlan?,
        sourceSpaceId: UUID?,
        isSelected: Bool,
        fallbackRegularTabID: UUID?
    ) -> Bool {
        let previousSessionState = ShortcutConversionWindowSessionState(state)
        let selectedSourceGroupID = splitTransition.sourceGroupID.flatMap { groupId in
            state.splitSelection?.groupID == groupId
                && state.splitSelection?.activeMemberID == .regularTab(originalTabId)
                ? groupId
                : nil
        }
        if isSelected || selectedSourceGroupID != nil,
           let terminalSelection {
            terminalSelection.apply(to: &state)
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
            state.activeTabForSpace[sourceSpaceId] = fallbackRegularTabID
        }
        state.selectionHistory.removeFromRegularTabHistory(originalTabId)
        return previousSessionState != ShortcutConversionWindowSessionState(state)
    }
}
