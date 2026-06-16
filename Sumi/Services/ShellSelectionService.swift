import Foundation

@MainActor
protocol ShellSelectionTabStore: AnyObject {
    var spaces: [Space] { get }

    func tab(for id: UUID) -> Tab?
    func tabs(in space: Space) -> [Tab]
    func shortcutPin(by id: UUID) -> ShortcutPin?
    func activeShortcutTab(for windowId: UUID) -> Tab?
    func liveShortcutTabs(in windowId: UUID) -> [Tab]
    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab?
}

@MainActor
final class ShellSelectionService {
    typealias SplitTabProvider = (_ windowId: UUID) -> [UUID]

    private let splitTabsForWindow: SplitTabProvider

    init(splitTabsForWindow: @escaping SplitTabProvider) {
        self.splitTabsForWindow = splitTabsForWindow
    }

    func currentTab(
        for windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> Tab? {
        if windowState.isIncognito {
            return windowState.ephemeralTabs.first { $0.id == windowState.currentTabId }
        }

        if let tabId = windowState.currentTabId,
           let current = tabStore.tab(for: tabId),
           isSelectableTab(current),
           tabBelongsToDisplayedContext(current, in: windowState)
        {
            return current
        }

        if let currentSpace = space(for: windowState.currentSpaceId, tabStore: tabStore) {
            return preferredTabForSpace(currentSpace, in: windowState, tabStore: tabStore)
        }

        return preferredTabForWindow(windowState, tabStore: tabStore)
    }

    func preferredTabForWindow(
        _ windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> Tab? {
        if windowState.isShowingEmptyState {
            return nil
        }

        if let shortcutPinId = windowState.currentShortcutPinId,
           let pin = tabStore.shortcutPin(by: shortcutPinId)
        {
            // Selection reads are used from SwiftUI body; activation must stay in explicit actions/restoration.
            return tabStore.activeShortcutTab(for: windowState.id)
                ?? tabStore.shortcutLiveTab(for: pin.id, in: windowState.id)
        }

        if let currentSpaceId = windowState.currentSpaceId,
           let tabId = windowState.activeTabForSpace[currentSpaceId],
           let remembered = tabStore.tab(for: tabId),
           isSelectableTab(remembered)
        {
            return remembered
        }

        if let currentSpaceId = windowState.currentSpaceId,
           let space = tabStore.spaces.first(where: { $0.id == currentSpaceId }),
           let activeTabId = space.activeTabId,
           let active = tabStore.tab(for: activeTabId),
           isSelectableTab(active)
        {
            return active
        }

        return nil
    }

    func preferredRegularTabForWindow(
        _ windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> Tab? {
        if let currentSpaceId = windowState.currentSpaceId,
           let space = tabStore.spaces.first(where: { $0.id == currentSpaceId })
        {
            let regularTabs = tabStore.tabs(in: space)
            let regularTabById = tabLookup(for: regularTabs)
            if let historyMatch = firstTab(
                matching: windowState.recentRegularTabIdsBySpace[currentSpaceId],
                in: regularTabById
            ) {
                return historyMatch
            }

            if let rememberedId = windowState.activeTabForSpace[currentSpaceId],
               let remembered = regularTabById[rememberedId]
            {
                return remembered
            }

            if let activeId = space.activeTabId,
               let active = regularTabById[activeId]
            {
                return active
            }

            return regularTabs.first
        }

        return nil
    }

    func preferredTabForSpace(
        _ space: Space,
        in windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> Tab? {
        if let shortcutPinId = windowState.selectedShortcutPinForSpace[space.id],
           let liveShortcut = tabStore.shortcutLiveTab(for: shortcutPinId, in: windowState.id)
        {
            return liveShortcut
        }

        let regularTabs = tabStore.tabs(in: space)
        let regularTabById = tabLookup(for: regularTabs)
        if let historyMatch = firstTab(
            matching: windowState.recentRegularTabIdsBySpace[space.id],
            in: regularTabById
        ) {
            return historyMatch
        }

        if let rememberedId = windowState.activeTabForSpace[space.id],
           let remembered = regularTabById[rememberedId]
        {
            return remembered
        }

        if let activeId = space.activeTabId,
           let active = regularTabById[activeId]
        {
            return active
        }

        if let backgroundShortcut = tabStore.liveShortcutTabs(in: windowState.id)
            .first(where: { $0.shortcutPinRole != .essential && $0.spaceId == space.id })
        {
            return backgroundShortcut
        }

        return regularTabs.first
    }

    func tabsForDisplay(
        in windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> [Tab] {
        if windowState.isIncognito {
            return windowState.ephemeralTabs
        }

        let currentSpace = windowState.currentSpaceId.flatMap { id in
            tabStore.spaces.first(where: { $0.id == id })
        }
        let regularTabs = currentSpace.map { tabStore.tabs(in: $0) } ?? []
        let activeShortcut = tabStore.activeShortcutTab(for: windowState.id)

        if let activeShortcut,
           activeShortcut.spaceId == nil || activeShortcut.spaceId == currentSpace?.id
        {
            return [activeShortcut] + regularTabs
        }

        return regularTabs
    }

    func tabsForWebExtensionWindow(
        in windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> [Tab] {
        if windowState.isIncognito {
            return windowState.ephemeralTabs
        }

        let splitTabs = splitTabsForWindow(windowState.id)
        var orderedTabs = tabsForDisplay(in: windowState, tabStore: tabStore)

        func appendIfMissing(_ tab: Tab?) {
            guard let tab else { return }
            guard orderedTabs.contains(where: { $0.id == tab.id }) == false else {
                return
            }
            orderedTabs.append(tab)
        }

        appendIfMissing(currentTab(for: windowState, tabStore: tabStore))
        splitTabs.forEach { appendIfMissing(tabStore.tab(for: $0)) }

        return orderedTabs
    }

    func windowScopedMediaCandidateTabs(
        in windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> [Tab] {
        if windowState.isIncognito {
            return windowState.ephemeralTabs
        }

        let liveShortcutTabs = tabStore.liveShortcutTabs(in: windowState.id)
        let regularTabs = tabStore.spaces.flatMap { tabStore.tabs(in: $0) }

        var seen = Set<UUID>()
        return (liveShortcutTabs + regularTabs).filter { tab in
            seen.insert(tab.id).inserted
        }
    }

    func hasValidCurrentSelection(
        in windowState: BrowserWindowState,
        tabStore: ShellSelectionTabStore
    ) -> Bool {
        guard let currentTabId = windowState.currentTabId,
              let tab = tabStore.tab(for: currentTabId)
        else {
            return false
        }

        return tabBelongsToDisplayedContext(tab, in: windowState)
    }

    func tabBelongsToDisplayedContext(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) -> Bool {
        if tab.isShortcutLiveInstance && tab.shortcutPinRole == .essential {
            return true
        }

        guard let currentSpaceId = windowState.currentSpaceId else {
            return !tab.isShortcutLiveInstance || tab.shortcutPinRole == .essential
        }

        let splitTabs = splitTabsForWindow(windowState.id)
        if splitTabs.contains(tab.id) {
            return true
        }

        if tab.isShortcutLiveInstance {
            return tab.spaceId == nil || tab.spaceId == currentSpaceId
        }

        return tab.spaceId == currentSpaceId
    }

    private func isSelectableTab(_ tab: Tab) -> Bool {
        if tab.isShortcutLiveInstance {
            return true
        }

        return !tab.isPinned && !tab.isSpacePinned
    }

    private func tabLookup(for tabs: [Tab]) -> [UUID: Tab] {
        tabs.reduce(into: [:]) { lookup, tab in
            if lookup[tab.id] == nil {
                lookup[tab.id] = tab
            }
        }
    }

    private func firstTab(matching tabIds: [UUID]?, in tabsById: [UUID: Tab]) -> Tab? {
        guard let tabIds else { return nil }
        for tabId in tabIds {
            if let tab = tabsById[tabId] {
                return tab
            }
        }
        return nil
    }

    func space(
        for spaceId: UUID?,
        tabStore: ShellSelectionTabStore
    ) -> Space? {
        guard let spaceId else { return nil }
        return tabStore.spaces.first(where: { $0.id == spaceId })
    }
}
