import Foundation
import SumiWebRuntime

/// Resolves the tabs presented by an exact browser window. The service reads
/// only shell-window state plus tab/split projections and does not reach back
/// through BrowserManager.
@MainActor
final class BrowserWindowTabContext {
    private let selectionService: ShellSelectionService
    private let tabStore: any ShellSelectionTabStore
    private weak var windows: WindowRegistry?
    private let splitQuery: WindowSplitQuery
    private let webViewSessions: WebViewSessionRepository

    init(
        selectionService: ShellSelectionService,
        tabStore: any ShellSelectionTabStore,
        windows: WindowRegistry,
        splitQuery: WindowSplitQuery,
        webViewSessions: WebViewSessionRepository
    ) {
        self.selectionService = selectionService
        self.tabStore = tabStore
        self.windows = windows
        self.splitQuery = splitQuery
        self.webViewSessions = webViewSessions
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        guard !windowState.restorationState.isAwaitingInitialResolution else {
            return nil
        }

        return selectionService.currentTab(
            for: windowState,
            tabStore: tabStore
        )
    }

    func currentSplitTabs(in windowState: BrowserWindowState) -> [Tab] {
        let tabIDs = splitQuery.visibleTabIDs(in: windowState.id)
        guard let currentTabID = windowState.currentTabId,
              tabIDs.contains(currentTabID) else {
            return []
        }
        return tabIDs.compactMap(tabStore.tab(for:))
    }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        selectionService.hasValidCurrentSelection(
            in: windowState,
            tabStore: tabStore
        )
    }

    func selectionTarget(
        for space: Space,
        in windowState: BrowserWindowState
    ) -> Tab? {
        selectionService.selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState,
            tabStore: tabStore
        )
    }

    func windowState(containing tab: Tab) -> BrowserWindowState? {
        windows?.allWindows.first { windowState in
            if windowState.isIncognito {
                return windowState.ephemeralTabs.contains { $0.id == tab.id }
            }
            if windowState.currentTabId == tab.id {
                return true
            }
            if tabStore.liveShortcutTabs(in: windowState.id).contains(where: { $0.id == tab.id }) {
                return true
            }
            return splitQuery.contains(tabID: tab.id, in: windowState.id)
        }
    }

    func tabsForDisplay(in windowState: BrowserWindowState) -> [Tab] {
        selectionService.tabsForDisplay(
            in: windowState,
            tabStore: tabStore
        )
    }

    /// Tab identities durably or physically adopted by this shell. Unlike
    /// `tabsForDisplay`, this does not project every durable Tab in the shared
    /// Space, and it remains valid while a selected Tab is suspended.
    func windowLocalTabResidenceIDs(
        in windowState: BrowserWindowState
    ) -> Set<UUID> {
        var tabIDs = Set(splitQuery.visibleTabIDs(in: windowState.id))
        tabIDs.formUnion(
            webViewSessions.trackedWebViews(in: windowState.id).map { $0.0.tabID }
        )
        tabIDs.formUnion(tabStore.liveShortcutTabs(in: windowState.id).map(\.id))
        if windowState.isIncognito {
            tabIDs.formUnion(windowState.ephemeralTabs.map(\.id))
        }
        if let currentTabID = windowState.currentTabId {
            tabIDs.insert(currentTabID)
        }
        return tabIDs
    }

    func isTabDisplayedInAnyWindow(_ tabId: UUID) -> Bool {
        windows?.allWindows.contains { windowState in
            tabsForDisplay(in: windowState).contains { $0.id == tabId }
        } ?? false
    }

    func windowScopedMediaCandidateTabs(
        in windowState: BrowserWindowState
    ) -> [Tab] {
        selectionService.windowScopedMediaCandidateTabs(
            in: windowState,
            tabStore: tabStore
        )
    }
}
