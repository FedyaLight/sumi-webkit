import Foundation

@MainActor
final class BrowserTabCloseFallbackPlanner {
    private let selectionService: ShellSelectionService

    init(selectionService: ShellSelectionService) {
        self.selectionService = selectionService
    }

    func fallbackAfterClosingRegularTab(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> Tab? {
        let targetSpaceId = tab.spaceId ?? windowState.currentSpaceId
        guard let targetSpaceId,
              let space = tabStore.spaces.first(where: { $0.id == targetSpaceId })
        else {
            return selectionService.preferredRegularTabForWindow(
                windowState,
                tabStore: tabStore
            )
        }

        let spaceTabs = tabStore.tabs(in: space)
        let regularTabs = spaceTabs.filter { $0.id != tab.id }
        let regularTabById = tabLookup(excluding: tab.id, in: spaceTabs)
        if let historyMatch = historicalFallbackTab(
            afterClosing: tab,
            in: windowState,
            targetSpaceId: targetSpaceId,
            regularTabsById: regularTabById,
            tabStore: tabStore
        ) {
            return historyMatch
        }

        guard !regularTabs.isEmpty else {
            return nil
        }

        if let historyMatch = firstTab(
            matching: windowState.recentRegularTabIdsBySpace[targetSpaceId],
            in: regularTabById
        ) {
            return historyMatch
        }

        if let closingIndex = spaceTabs.firstIndex(where: { $0.id == tab.id }) {
            if regularTabs.indices.contains(closingIndex) {
                return regularTabs[closingIndex]
            }
            if regularTabs.indices.contains(max(0, closingIndex - 1)) {
                return regularTabs[max(0, closingIndex - 1)]
            }
        }

        return regularTabs.last
    }

    func fallbackAfterClosingShortcutLiveTab(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> Tab? {
        historicalFallbackTab(
            afterClosing: tab,
            in: windowState,
            tabStore: tabStore
        )
        ?? selectionService.preferredRegularTabForWindow(
            windowState,
            tabStore: tabStore
        )
    }

    private func historicalFallbackTab(
        afterClosing tab: Tab,
        in windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> Tab? {
        let targetSpaceId = tab.spaceId ?? windowState.currentSpaceId
        guard let targetSpaceId,
              let space = tabStore.spaces.first(where: { $0.id == targetSpaceId })
        else {
            return nil
        }

        return historicalFallbackTab(
            afterClosing: tab,
            in: windowState,
            targetSpaceId: targetSpaceId,
            regularTabsById: tabLookup(excluding: tab.id, in: tabStore.tabs(in: space)),
            tabStore: tabStore
        )
    }

    private func historicalFallbackTab(
        afterClosing tab: Tab,
        in windowState: BrowserWindowState,
        targetSpaceId: UUID,
        regularTabsById: [Tab.ID: Tab],
        tabStore: ShellSelectionTabStore
    ) -> Tab? {
        for item in windowState.recentSelectionItemsBySpace[targetSpaceId] ?? [] {
            switch item {
            case let .regularTab(tabId):
                if let regularTab = regularTabsById[tabId] {
                    return regularTab
                }
            case let .shortcutPin(pinId):
                if let liveTab = tabStore.shortcutLiveTab(for: pinId, in: windowState.id),
                   liveTab.id != tab.id,
                   liveTab.shortcutPinRole == .essential || liveTab.spaceId == targetSpaceId {
                    return liveTab
                }
            }
        }

        return nil
    }

    private func tabLookup(excluding excludedTabId: Tab.ID, in tabs: [Tab]) -> [Tab.ID: Tab] {
        tabs.reduce(into: [:]) { lookup, tab in
            guard tab.id != excludedTabId, lookup[tab.id] == nil else { return }
            lookup[tab.id] = tab
        }
    }

    private func firstTab(matching tabIds: [Tab.ID]?, in tabsById: [Tab.ID: Tab]) -> Tab? {
        guard let tabIds else { return nil }
        for tabId in tabIds {
            if let tab = tabsById[tabId] {
                return tab
            }
        }
        return nil
    }
}
