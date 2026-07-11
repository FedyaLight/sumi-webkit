import Foundation

@MainActor
enum DisplayedTabShortcutWindowTransition {
    static func apply(
        to windowState: BrowserWindowState,
        originalTabId: UUID,
        liveTab: Tab?,
        sourceSpaceId: UUID?,
        isSelected: Bool,
        regularTabs: RegularTabCollectionOwner
    ) -> Bool {
        let previousSessionState = ShortcutConversionWindowSessionState(
            windowState
        )
        if isSelected, let liveTab {
            _ = WindowTabSelectionStateApplicator.apply(
                liveTab,
                to: windowState,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        }
        if let sourceSpaceId,
           windowState.activeTabForSpace[sourceSpaceId] == originalTabId {
            windowState.activeTabForSpace[sourceSpaceId] = regularTabs
                .tabs(in: sourceSpaceId)
                .first?.id
        }
        windowState.selectionHistory.removeFromRegularTabHistory(originalTabId)
        return previousSessionState
            != ShortcutConversionWindowSessionState(windowState)
    }
}
