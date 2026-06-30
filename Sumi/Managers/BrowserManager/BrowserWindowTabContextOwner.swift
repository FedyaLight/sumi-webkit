import Foundation

@MainActor
final class BrowserWindowTabContextOwner {
    struct Dependencies {
        let selectionService: @MainActor () -> ShellSelectionService?
        let tabStore: @MainActor () -> ShellSelectionTabStore?
        let windows: @MainActor () -> [BrowserWindowState]
        let liveShortcutTabs: @MainActor (UUID) -> [Tab]
        let visibleSplitTabIds: @MainActor (UUID) -> Set<UUID>
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        guard !windowState.isAwaitingInitialSessionResolution,
              let selectionService = dependencies.selectionService(),
              let tabStore = dependencies.tabStore()
        else {
            return nil
        }

        return selectionService.currentTab(
            for: windowState,
            tabStore: tabStore
        )
    }

    func windowState(containing tab: Tab) -> BrowserWindowState? {
        dependencies.windows().first { windowState in
            if windowState.isIncognito {
                return windowState.ephemeralTabs.contains { $0.id == tab.id }
            }

            if windowState.currentTabId == tab.id {
                return true
            }

            if dependencies.liveShortcutTabs(windowState.id).contains(where: { $0.id == tab.id }) {
                return true
            }

            if dependencies.visibleSplitTabIds(windowState.id).contains(tab.id) {
                return true
            }

            return false
        }
    }

    func tabsForDisplay(in windowState: BrowserWindowState) -> [Tab] {
        guard let selectionService = dependencies.selectionService(),
              let tabStore = dependencies.tabStore()
        else {
            return []
        }

        return selectionService.tabsForDisplay(
            in: windowState,
            tabStore: tabStore
        )
    }

    func isTabDisplayedInAnyWindow(_ tabId: UUID) -> Bool {
        dependencies.windows().contains { windowState in
            tabsForDisplay(in: windowState).contains { $0.id == tabId }
        }
    }

    func windowScopedMediaCandidateTabs(in windowState: BrowserWindowState) -> [Tab] {
        guard let selectionService = dependencies.selectionService(),
              let tabStore = dependencies.tabStore()
        else {
            return []
        }

        return selectionService.windowScopedMediaCandidateTabs(
            in: windowState,
            tabStore: tabStore
        )
    }
}
