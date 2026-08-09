import Foundation

@MainActor
struct WindowSessionSelectionReconciler {
    let membership: TabCollectionMembershipOwner
    let tabStore: any ShellSelectionTabStore
    let selectionService: ShellSelectionService
    let selection: any WindowSessionSelectionApplying
    let spaceResolver: WindowSessionSpaceResolver

    func discardMissingTabAfterInitialDataLoad(
        _ windowState: BrowserWindowState
    ) {
        if let currentTabId = windowState.currentTabId,
           membership.tab(for: currentTabId) == nil {
            windowState.currentTabId = nil
        }
    }

    func resolveMissingSelectionAfterInitialDataLoad(
        _ windowState: BrowserWindowState
    ) {
        if windowState.currentTabId == nil,
           windowState.isShowingEmptyState == false {
            if let restoredTab = preferredTabForWindow(windowState) {
                windowState.currentTabId = restoredTab.id
            } else {
                selection.showEmptyState(
                    in: windowState,
                    presentNewTabCommandPalette: false
                )
            }
        }
    }

    func activateResolvedSelectionAfterInitialDataLoad(
        _ windowState: BrowserWindowState
    ) {
        guard let currentTabID = windowState.currentTabId,
              let currentTab = membership.tab(for: currentTabID) else {
            return
        }
        apply(currentTab, to: windowState)
    }

    func reconcileFinalSelection(
        _ windowState: BrowserWindowState
    ) {
        if windowState.isShowingEmptyState == false,
           hasValidCurrentSelection(in: windowState) == false {
            if let currentSpace = spaceResolver.space(
                for: windowState.currentSpaceId
            ),
               let preferred = selectionService.preferredTabForSpace(
                currentSpace,
                in: windowState,
                tabStore: tabStore
               ) {
                apply(preferred, to: windowState)
            } else if let preferred = preferredTabForWindow(windowState) {
                apply(preferred, to: windowState)
            }
        }

        if windowState.isShowingEmptyState,
           let currentSpace = spaceResolver.space(
            for: windowState.currentSpaceId
           ),
           let preferred = selectionService.preferredTabForSpace(
            currentSpace,
            in: windowState,
            tabStore: tabStore
           ) {
            apply(preferred, to: windowState)
        }

        if windowState.currentTabId == nil,
           preferredTabForWindow(windowState) == nil {
            windowState.isShowingEmptyState = true
        }
    }

    private func hasValidCurrentSelection(
        in windowState: BrowserWindowState
    ) -> Bool {
        selectionService.hasValidCurrentSelection(
            in: windowState,
            tabStore: tabStore
        )
    }

    private func preferredTabForWindow(
        _ windowState: BrowserWindowState
    ) -> Tab? {
        selectionService.preferredTabForWindow(
            windowState,
            tabStore: tabStore
        )
    }

    private func apply(
        _ tab: Tab,
        to windowState: BrowserWindowState
    ) {
        selection.applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: false,
            updateTheme: false,
            rememberSelection: false,
            persistSelection: false
        )
    }
}
