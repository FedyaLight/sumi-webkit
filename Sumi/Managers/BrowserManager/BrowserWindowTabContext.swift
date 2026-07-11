import Foundation

/// Resolves the tabs presented by an exact browser window. The service reads
/// only shell-window state plus tab/split projections and does not reach back
/// through BrowserManager.
@MainActor
final class BrowserWindowTabContext {
    private let selectionService: @MainActor () -> ShellSelectionService?
    private let tabStore: @MainActor () -> ShellSelectionTabStore?
    private let windows: @MainActor () -> [BrowserWindowState]
    private let liveShortcutTabs: @MainActor (UUID) -> [Tab]
    private let visibleSplitTabIds: @MainActor (UUID) -> Set<UUID>
    private let trackedTabIds: @MainActor (UUID) -> Set<UUID>

    init(
        selectionService: @escaping @MainActor () -> ShellSelectionService?,
        tabStore: @escaping @MainActor () -> ShellSelectionTabStore?,
        windows: @escaping @MainActor () -> [BrowserWindowState],
        liveShortcutTabs: @escaping @MainActor (UUID) -> [Tab],
        visibleSplitTabIds: @escaping @MainActor (UUID) -> Set<UUID>,
        trackedTabIds: @escaping @MainActor (UUID) -> Set<UUID> = { _ in [] }
    ) {
        self.selectionService = selectionService
        self.tabStore = tabStore
        self.windows = windows
        self.liveShortcutTabs = liveShortcutTabs
        self.visibleSplitTabIds = visibleSplitTabIds
        self.trackedTabIds = trackedTabIds
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

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        guard let selectionService = selectionService(),
              let tabStore = tabStore() else {
            return false
        }
        return selectionService.hasValidCurrentSelection(
            in: windowState,
            tabStore: tabStore
        )
    }

    func selectionTarget(
        for space: Space,
        in windowState: BrowserWindowState
    ) -> Tab? {
        guard let selectionService = selectionService(),
              let tabStore = tabStore() else {
            return nil
        }
        return selectionService.selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState,
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
            return visibleSplitTabIds(windowState.id).contains(tab.id)
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

    /// Tab identities durably or physically adopted by this shell. Unlike
    /// `tabsForDisplay`, this does not project every durable Tab in the shared
    /// Space, and it remains valid while a selected Tab is suspended.
    func windowLocalTabResidenceIDs(
        in windowState: BrowserWindowState
    ) -> Set<UUID> {
        var tabIDs = visibleSplitTabIds(windowState.id)
        tabIDs.formUnion(trackedTabIds(windowState.id))
        tabIDs.formUnion(liveShortcutTabs(windowState.id).map(\.id))
        if windowState.isIncognito {
            tabIDs.formUnion(windowState.ephemeralTabs.map(\.id))
        }
        if let currentTabID = windowState.currentTabId {
            tabIDs.insert(currentTabID)
        }
        return tabIDs
    }

    func isTabDisplayedInAnyWindow(_ tabId: UUID) -> Bool {
        windows().contains { windowState in
            tabsForDisplay(in: windowState).contains { $0.id == tabId }
        }
    }

    func windowScopedMediaCandidateTabs(
        in windowState: BrowserWindowState
    ) -> [Tab] {
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
