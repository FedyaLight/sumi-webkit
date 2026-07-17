import Foundation

@MainActor
final class BrowserTabSelectionStateApplication {
    private let windows: WindowRegistry
    private let windowSelection: ShellSelectionService
    private let tabStore: any ShellSelectionTabStore
    private let spaces: TabSpaceCollectionStateOwner
    private let splitMembership: SplitGroupMembershipQuery

    init(
        windows: WindowRegistry,
        windowSelection: ShellSelectionService,
        tabStore: any ShellSelectionTabStore,
        spaces: TabSpaceCollectionStateOwner,
        splitMembership: SplitGroupMembershipQuery
    ) {
        self.windows = windows
        self.windowSelection = windowSelection
        self.tabStore = tabStore
        self.spaces = spaces
        self.splitMembership = splitMembership
    }

    var activeWindowID: UUID? {
        windows.activeWindow?.id
    }

    func window(_ windowID: UUID) -> BrowserWindowState? {
        windows.windows[windowID]
    }

    func resolvedTab(_ tabID: UUID, in windowState: BrowserWindowState) -> Tab? {
        tabStore.tab(for: tabID)
            ?? windowState.ephemeralTabs.first(where: { $0.id == tabID })
    }

    func currentTab(in windowState: BrowserWindowState) -> Tab? {
        windowSelection.currentTab(for: windowState, tabStore: tabStore)
    }

    func space(_ spaceID: UUID?) -> Space? {
        spaceID.flatMap { id in
            spaces.spaces.first(where: { $0.id == id })
        }
    }

    func selectionTarget(
        in space: Space,
        windowState: BrowserWindowState
    ) -> Tab? {
        windowSelection.selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState,
            tabStore: tabStore
        )
    }

    func apply(
        _ tab: Tab,
        to windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        rememberSelection: Bool
    ) -> WindowTabSelectionApplicationResult {
        WindowTabSelectionStateApplicator.apply(
            tab,
            to: windowState,
            updateSpaceFromTab: updateSpaceFromTab,
            rememberSelection: rememberSelection
        )
    }

    func reconcileSplitSelection(
        for tab: Tab,
        in windowState: BrowserWindowState
    ) {
        let memberID = splitMembership.memberID(for: tab)
        guard let group = splitMembership.group(containing: memberID) else {
            windowState.splitSelection = nil
            return
        }
        windowState.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: memberID
        )
    }

    func synchronizeShortcutSelection(in windowState: BrowserWindowState) {
        guard let currentTabID = windowState.currentTabId else {
            if !windowState.isShowingEmptyState {
                windowState.currentShortcutPinId = nil
                windowState.currentShortcutPinRole = nil
            }
            return
        }

        if let liveShortcutTab = tabStore.liveShortcutTabs(in: windowState.id)
            .first(where: { $0.id == currentTabID && $0.isShortcutLiveInstance }) {
            windowState.currentShortcutPinId = liveShortcutTab.shortcutPinId
            windowState.currentShortcutPinRole = liveShortcutTab.shortcutPinRole
        } else {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
        }
    }

    func installEmptyState(in windowState: BrowserWindowState) {
        windowState.currentTabId = nil
        windowState.currentShortcutPinId = nil
        windowState.currentShortcutPinRole = nil
        windowState.splitSelection = nil
        windowState.isShowingEmptyState = true
    }
}
