import Foundation

@MainActor
struct WindowSessionSnapshotFactory {
    typealias WindowGeometryProvider = @MainActor (
        BrowserWindowState
    ) -> BrowserWindowGeometrySnapshot?
    typealias LiveShortcutProvider = @MainActor (
        BrowserWindowState
    ) -> [ShortcutLiveSessionSnapshot]

    let glanceManager: GlanceManager
    let windowGeometry: WindowGeometryProvider
    let liveShortcuts: LiveShortcutProvider

    init(
        glanceManager: GlanceManager,
        windowGeometry: @escaping WindowGeometryProvider = { _ in nil },
        liveShortcuts: @escaping LiveShortcutProvider = { _ in [] }
    ) {
        self.glanceManager = glanceManager
        self.windowGeometry = windowGeometry
        self.liveShortcuts = liveShortcuts
    }

    func make(for windowState: BrowserWindowState) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: windowState.currentTabId,
            currentSpaceId: windowState.currentSpaceId,
            currentProfileId: windowState.currentProfileId,
            activeShortcutPinId: windowState.currentShortcutPinId,
            activeShortcutPinRole: windowState.currentShortcutPinRole,
            isShowingEmptyState: windowState.isShowingEmptyState,
            commandPaletteReason: windowState.commandPalettePresentationReason,
            activeTabsBySpace: windowState.activeTabForSpace.map {
                SpaceTabSelectionSnapshot(spaceId: $0.key, tabId: $0.value)
            },
            activeShortcutsBySpace: windowState.selectedShortcutPinForSpace.map {
                SpaceShortcutSelectionSnapshot(
                    spaceId: $0.key,
                    shortcutPinId: $0.value
                )
            },
            selectionHistory: WindowSelectionHistorySnapshot(
                windowState.selectionHistory
            ),
            liveShortcuts: liveShortcuts(windowState),
            collapsedPinnedSpaceIDs: windowState.sidebarSpacePinnedCollapse
                .persistedCollapsedSpaceIDs,
            sidebarWidth: Double(windowState.sidebarWidth),
            savedSidebarWidth: Double(windowState.savedSidebarWidth),
            sidebarContentWidth: Double(windowState.sidebarContentWidth),
            isSidebarVisible: windowState.isSidebarVisible,
            commandPaletteDraft: CommandPaletteDraftState(
                text: windowState.commandPaletteDraftText,
                navigateCurrentTab: windowState
                    .commandPaletteDraftNavigatesCurrentTab
            ),
            splitSelection: windowState.splitSelection,
            glanceSession: glanceManager
                .makeSessionSnapshot(for: windowState),
            windowGeometry: windowGeometry(windowState)
        )
    }
}
