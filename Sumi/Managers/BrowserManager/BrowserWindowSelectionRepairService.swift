import Foundation

/// Repairs one window's selection after structural tab mutations. The service
/// does not persist or refresh UI; it reports whether its caller must commit.
@MainActor
final class BrowserWindowSelectionRepairService {
    private let tabManager: TabManager
    private let selection: ShellSelectionService
    private let synchronizeShortcutSelection: (BrowserWindowState) -> Void
    private let applyTabSelection: (Tab, BrowserWindowState) -> Void
    private let showEmptyState: (BrowserWindowState) -> Void

    init(
        tabManager: TabManager,
        selection: ShellSelectionService,
        synchronizeShortcutSelection: @escaping (BrowserWindowState) -> Void,
        applyTabSelection: @escaping (Tab, BrowserWindowState) -> Void,
        showEmptyState: @escaping (BrowserWindowState) -> Void
    ) {
        self.tabManager = tabManager
        self.selection = selection
        self.synchronizeShortcutSelection = synchronizeShortcutSelection
        self.applyTabSelection = applyTabSelection
        self.showEmptyState = showEmptyState
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            tabManager: browserManager.tabManager,
            selection: browserManager.shellRuntime.windowSelection,
            synchronizeShortcutSelection: { [weak browserManager] windowState in
                browserManager?.syncShortcutSelectionState(for: windowState)
            },
            applyTabSelection: { [weak browserManager] tab, windowState in
                browserManager?.applyTabSelection(
                    tab,
                    in: windowState,
                    updateSpaceFromTab: false,
                    updateTheme: false,
                    rememberSelection: false,
                    persistSelection: false
                )
            },
            showEmptyState: { [weak browserManager] windowState in
                browserManager?.showEmptyState(in: windowState)
            }
        )
    }

    @discardableResult
    func reconcile(_ windowState: BrowserWindowState) -> Bool {
        guard !windowState.isAwaitingInitialSessionResolution else { return false }

        var didChange = clearMissingCurrentTab(in: windowState)

        if !windowState.isShowingEmptyState,
           !hasValidCurrentSelection(in: windowState) {
            if let preferredTab = preferredTab(in: windowState) {
                applyTabSelection(preferredTab, windowState)
            } else {
                showEmptyState(windowState)
            }
            didChange = true
        }

        let previousShortcutPinId = windowState.currentShortcutPinId
        synchronizeShortcutSelection(windowState)
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
            tabExists = tabManager.tabCollectionMembershipOwner.tab(for: currentTabId) != nil
        }

        guard !tabExists else { return false }
        windowState.currentTabId = nil
        return true
    }

    private func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        selection.hasValidCurrentSelection(
            in: windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    private func preferredTab(in windowState: BrowserWindowState) -> Tab? {
        if let currentSpaceId = windowState.currentSpaceId,
           let currentSpace = tabManager.spaceStateOwner.space(with: currentSpaceId),
           let preferred = selection.preferredTabForSpace(
               currentSpace,
               in: windowState,
               tabStore: tabManager.runtimeStore
           ) {
            return preferred
        }

        return selection.preferredTabForWindow(
            windowState,
            tabStore: tabManager.runtimeStore
        )
    }
}
