import Foundation

@MainActor
final class BrowserTabCloseFallbackPlanner {
    private let selectionService: ShellSelectionService
    private let tabStore: any ShellSelectionTabStore

    init(
        selectionService: ShellSelectionService,
        tabStore: any ShellSelectionTabStore
    ) {
        self.selectionService = selectionService
        self.tabStore = tabStore
    }

    func fallbackAfterClosingRegularTab(
        _ tab: Tab,
        in windowState: BrowserWindowState
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
            in: windowState,
            targetSpaceId: targetSpaceId,
            excludingTabIds: [tab.id],
            excludingShortcutPinIds: [],
            tabStore: tabStore
        ) {
            return historyMatch
        }

        guard !regularTabs.isEmpty else {
            return nil
        }

        if let historyMatch = firstTab(
            matching: windowState.selectionHistory.recentRegularTabIdsBySpace[targetSpaceId],
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
        in windowState: BrowserWindowState
    ) -> Tab? {
        let targetSpaceId = tab.spaceId ?? windowState.currentSpaceId
        let excludedPinIds = tab.shortcutPinId.map { Set([$0]) } ?? []
        return historicalFallbackTab(
            in: windowState,
            targetSpaceId: targetSpaceId,
            excludingTabIds: [tab.id],
            excludingShortcutPinIds: excludedPinIds,
            tabStore: tabStore
        )
        ?? selectionService.preferredRegularTabForWindow(
            windowState,
            tabStore: tabStore
        )
    }

    func fallbackAfterClosingShortcutLiveTabs(
        excludingShortcutPinIds pinIds: Set<UUID>,
        in windowState: BrowserWindowState
    ) -> Tab? {
        historicalFallbackTab(
            in: windowState,
            targetSpaceId: windowState.currentSpaceId,
            excludingTabIds: [],
            excludingShortcutPinIds: pinIds,
            tabStore: tabStore
        )
        ?? selectionService.preferredRegularTabForWindow(
            windowState,
            tabStore: tabStore
        )
    }

    private func historicalFallbackTab(
        in windowState: BrowserWindowState,
        targetSpaceId: UUID?,
        excludingTabIds: Set<Tab.ID>,
        excludingShortcutPinIds: Set<UUID>,
        tabStore: ShellSelectionTabStore
    ) -> Tab? {
        guard let targetSpaceId,
              let space = tabStore.spaces.first(where: {
                  $0.id == targetSpaceId
              })
        else { return nil }
        let regularTabsById = tabStore.tabs(in: space).reduce(
            into: [Tab.ID: Tab]()
        ) { lookup, tab in
            guard excludingTabIds.contains(tab.id) == false,
                  lookup[tab.id] == nil else { return }
            lookup[tab.id] = tab
        }
        let history = windowState.selectionHistory
            .recentSelectionItemsBySpace[targetSpaceId] ?? []
        for item in history {
            switch item {
            case let .regularTab(tabId):
                if let regularTab = regularTabsById[tabId] {
                    return regularTab
                }
            case let .shortcutPin(pinId):
                guard excludingShortcutPinIds.contains(pinId) == false else {
                    continue
                }
                if let liveTab = tabStore.shortcutLiveTab(
                    for: pinId,
                    in: windowState.id
                ),
                   excludingTabIds.contains(liveTab.id) == false,
                   liveTab.shortcutPinRole == .essential
                    || liveTab.spaceId == targetSpaceId {
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
