import Foundation

/// Computes the selection a window takes when a live shortcut tab closes.
///
/// Closing a tab that was not selected leaves the window's selection alone.
/// Closing the selected one hands over to the planner's fallback tab, or drops
/// the window to its empty state when nothing is left to select.
@MainActor
struct ShortcutLiveTabCloseSelectionTarget {
    private let fallbackPlanner: BrowserTabCloseFallbackPlanner
    private let splitMembership: SplitGroupMembershipQuery
    private let tabStore: any ShellSelectionTabStore
    private let selection: BrowserTabSelectionOwner

    init(
        fallbackPlanner: BrowserTabCloseFallbackPlanner,
        splitMembership: SplitGroupMembershipQuery,
        tabStore: any ShellSelectionTabStore,
        selection: BrowserTabSelectionOwner
    ) {
        self.fallbackPlanner = fallbackPlanner
        self.splitMembership = splitMembership
        self.tabStore = tabStore
        self.selection = selection
    }

    func target(
        afterClosing tab: Tab,
        in windowState: BrowserWindowState,
        wasCurrent: Bool
    ) -> BrowserWindowShortcutMutationState {
        var target = windowState.unpublishedShortcutMutationState
        guard wasCurrent else { return target }

        if let fallback = fallbackPlanner.fallbackAfterClosingShortcutLiveTab(
            tab,
            in: windowState
        ) {
            _ = WindowTabSelectionStateApplicator.applyFallback(
                fallback,
                to: &target,
                splitMembership: splitMembership,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        } else {
            target.currentTabId = nil
            target.currentShortcutPinId = nil
            target.currentShortcutPinRole = nil
            target.isShowingEmptyState = true
        }
        return target
    }

    func publishPreparedEffectsAfterClosing(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        previousSpaceID: UUID?
    ) {
        guard let fallbackID = windowState.currentTabId,
              let fallback = tabStore.tab(for: fallbackID) else {
            return
        }
        _ = selection.publishPreparedSelectionEffects(
            fallback,
            in: windowState,
            previousTabID: tab.id,
            previousSpaceID: previousSpaceID
        )
    }
}
