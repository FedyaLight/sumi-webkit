import Foundation

@MainActor
final class BrowserWindowTabContextOwner {
    private let selectionService: @MainActor () -> ShellSelectionService?
    private let tabStore: @MainActor () -> ShellSelectionTabStore?
    private let windows: @MainActor () -> [BrowserWindowState]
    private let liveShortcutTabs: @MainActor (UUID) -> [Tab]
    private let visibleSplitTabIds: @MainActor (UUID) -> Set<UUID>

    init(
        selectionService: @escaping @MainActor () -> ShellSelectionService?,
        tabStore: @escaping @MainActor () -> ShellSelectionTabStore?,
        windows: @escaping @MainActor () -> [BrowserWindowState],
        liveShortcutTabs: @escaping @MainActor (UUID) -> [Tab],
        visibleSplitTabIds: @escaping @MainActor (UUID) -> Set<UUID>
    ) {
        self.selectionService = selectionService
        self.tabStore = tabStore
        self.windows = windows
        self.liveShortcutTabs = liveShortcutTabs
        self.visibleSplitTabIds = visibleSplitTabIds
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        guard !windowState.isAwaitingInitialSessionResolution,
              let selectionService = selectionService(),
              let tabStore = tabStore()
        else {
            return nil
        }

        return selectionService.currentTab(
            for: windowState,
            tabStore: tabStore
        )
    }

    func windowState(containing tab: Tab) -> BrowserWindowState? {
        windows().first { windowState in
            if windowState.isIncognito {
                return windowState.ephemeralTabs.contains { $0.id == tab.id }
            }

            if windowState.currentTabId == tab.id {
                return true
            }

            if liveShortcutTabs(windowState.id).contains(where: { $0.id == tab.id }) {
                return true
            }

            if visibleSplitTabIds(windowState.id).contains(tab.id) {
                return true
            }

            return false
        }
    }

    func tabsForDisplay(in windowState: BrowserWindowState) -> [Tab] {
        guard let selectionService = selectionService(),
              let tabStore = tabStore()
        else {
            return []
        }

        return selectionService.tabsForDisplay(
            in: windowState,
            tabStore: tabStore
        )
    }

    func isTabDisplayedInAnyWindow(_ tabId: UUID) -> Bool {
        windows().contains { windowState in
            tabsForDisplay(in: windowState).contains { $0.id == tabId }
        }
    }

    func windowScopedMediaCandidateTabs(in windowState: BrowserWindowState) -> [Tab] {
        guard let selectionService = selectionService(),
              let tabStore = tabStore()
        else {
            return []
        }

        return selectionService.windowScopedMediaCandidateTabs(
            in: windowState,
            tabStore: tabStore
        )
    }
}
