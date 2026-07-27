import Foundation

@MainActor
struct WindowSessionSnapshotFactory {
    typealias WindowGeometryProvider = @MainActor (
        BrowserWindowState
    ) -> BrowserWindowGeometrySnapshot?

    let glanceManager: GlanceManager
    let windowGeometry: WindowGeometryProvider

    init(
        glanceManager: GlanceManager,
        windowGeometry: @escaping WindowGeometryProvider = { _ in nil }
    ) {
        self.glanceManager = glanceManager
        self.windowGeometry = windowGeometry
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
