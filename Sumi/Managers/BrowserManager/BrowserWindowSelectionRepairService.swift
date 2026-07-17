import Foundation

/// Repairs one window's selection after structural tab mutations. The service
/// does not persist or refresh UI; it reports whether its caller must commit.
@MainActor
final class BrowserWindowSelectionRepairService {
    private let membership: TabCollectionMembershipOwner
    private let spaces: TabSpaceCollectionStateOwner
    private let tabStore: any ShellSelectionTabStore
    private let selection: ShellSelectionService
    private let selectionOwner: BrowserTabSelectionOwner

    init(
        membership: TabCollectionMembershipOwner,
        spaces: TabSpaceCollectionStateOwner,
        tabStore: any ShellSelectionTabStore,
        selection: ShellSelectionService,
        selectionOwner: BrowserTabSelectionOwner
    ) {
        self.membership = membership
        self.spaces = spaces
        self.tabStore = tabStore
        self.selection = selection
        self.selectionOwner = selectionOwner
    }

    @discardableResult
    func reconcile(_ windowState: BrowserWindowState) -> Bool {
        guard !windowState.restorationState.isAwaitingInitialResolution else { return false }

        var didChange = clearMissingCurrentTab(in: windowState)

        if !windowState.isShowingEmptyState,
           !hasValidCurrentSelection(in: windowState) {
            if let preferredTab = preferredTab(in: windowState) {
                selectionOwner.applyTabSelection(
                    preferredTab,
                    in: windowState,
                    updateSpaceFromTab: false,
                    updateTheme: false,
                    rememberSelection: false,
                    persistSelection: false,
                    loadPolicy: .immediate
                )
            } else {
                selectionOwner.showEmptyState(in: windowState)
            }
            didChange = true
        }

        let previousShortcutPinId = windowState.currentShortcutPinId
        selectionOwner.syncShortcutSelectionState(for: windowState)
        if previousShortcutPinId != windowState.currentShortcutPinId {
            didChange = true
        }

        return didChange
    }

    private func clearMissingCurrentTab(in windowState: BrowserWindowState) -> Bool {
        guard let currentTabId = windowState.currentTabId else { return false }

        let tabExists: Bool
        if windowState.isIncognito {
            tabExists = windowState.ephemeralTabs.contains { $0.id == currentTabId }
        } else {
            tabExists = membership.tab(for: currentTabId) != nil
        }

        guard !tabExists else { return false }
        windowState.currentTabId = nil
        return true
    }

    private func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        selection.hasValidCurrentSelection(
            in: windowState,
            tabStore: tabStore
        )
    }

    private func preferredTab(in windowState: BrowserWindowState) -> Tab? {
        if let currentSpaceId = windowState.currentSpaceId,
           let currentSpace = spaces.space(with: currentSpaceId),
           let preferred = selection.preferredTabForSpace(
               currentSpace,
               in: windowState,
               tabStore: tabStore
           ) {
            return preferred
        }

        return selection.preferredTabForWindow(
            windowState,
            tabStore: tabStore
        )
    }
}
