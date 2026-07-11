import Foundation

@MainActor
struct WindowSessionSnapshotFactory {
    let glanceManager: GlanceManager

    func make(for windowState: BrowserWindowState) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: windowState.currentTabId,
            currentSpaceId: windowState.currentSpaceId,
            currentProfileId: windowState.currentProfileId,
            activeShortcutPinId: windowState.currentShortcutPinId,
            activeShortcutPinRole: windowState.currentShortcutPinRole,
            isShowingEmptyState: windowState.isShowingEmptyState,
            floatingBarReason: windowState.floatingBarPresentationReason,
            activeTabsBySpace: windowState.activeTabForSpace.map {
                SpaceTabSelectionSnapshot(spaceId: $0.key, tabId: $0.value)
            },
            activeShortcutsBySpace: windowState.selectedShortcutPinForSpace.map {
                SpaceShortcutSelectionSnapshot(
                    spaceId: $0.key,
                    shortcutPinId: $0.value
                )
            },
            sidebarWidth: Double(windowState.sidebarWidth),
            savedSidebarWidth: Double(windowState.savedSidebarWidth),
            sidebarContentWidth: Double(windowState.sidebarContentWidth),
            isSidebarVisible: windowState.isSidebarVisible,
            floatingBarDraft: FloatingBarDraftState(
                text: windowState.floatingBarDraftText,
                navigateCurrentTab: windowState
                    .floatingBarDraftNavigatesCurrentTab
            ),
            splitSelection: windowState.splitSelection,
            glanceSession: glanceManager
                .makeSessionSnapshot(for: windowState)
        )
    }
}
