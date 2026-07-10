import Foundation

@MainActor
struct WindowSessionSnapshotApplier {
    let glanceManager: GlanceManager
    let floatingBarSanitizer: any WindowSessionFloatingBarSanitizing

    func apply(
        _ snapshot: WindowSessionSnapshot,
        to windowState: BrowserWindowState
    ) {
        windowState.currentTabId = snapshot.currentTabId
        windowState.currentSpaceId = snapshot.currentSpaceId
        windowState.currentProfileId = snapshot.currentProfileId
        windowState.currentShortcutPinId = snapshot.activeShortcutPinId
        windowState.currentShortcutPinRole = snapshot.activeShortcutPinRole
        windowState.isShowingEmptyState = snapshot.isShowingEmptyState
        windowState.floatingBarPresentationReason = snapshot.isShowingEmptyState
            ? (snapshot.floatingBarReason ?? .none)
            : .none
        windowState.activeTabForSpace = Dictionary(
            uniqueKeysWithValues: snapshot.activeTabsBySpace.map {
                ($0.spaceId, $0.tabId)
            }
        )
        windowState.selectedShortcutPinForSpace = Dictionary(
            uniqueKeysWithValues: snapshot.activeShortcutsBySpace.map {
                ($0.spaceId, $0.shortcutPinId)
            }
        )

        let sidebarWidth = BrowserWindowState.clampedSidebarWidth(
            CGFloat(snapshot.sidebarWidth)
        )
        windowState.sidebarWidth = sidebarWidth
        windowState.savedSidebarWidth = BrowserWindowState.clampedSidebarWidth(
            CGFloat(snapshot.savedSidebarWidth)
        )
        windowState.sidebarContentWidth = BrowserWindowState
            .sidebarContentWidth(for: sidebarWidth)
        windowState.isSidebarVisible = snapshot.isSidebarVisible
        windowState.isDownloadsPopoverPresented = false
        windowState.floatingBarDraftText = snapshot.floatingBarDraft.text
        windowState.floatingBarDraftNavigatesCurrentTab = snapshot
            .floatingBarDraft.navigateCurrentTab

        if snapshot.activeSplitGroupId == nil,
           let legacyGroup = snapshot.legacySplitSessionForMigration?
            .makeSplitGroup(spaceId: snapshot.currentSpaceId) {
            windowState.pendingSessionLegacySplitGroup = legacyGroup
            windowState.pendingSessionSplitGroupId = legacyGroup.id
        } else {
            windowState.pendingSessionLegacySplitGroup = nil
            windowState.pendingSessionSplitGroupId = snapshot.activeSplitGroupId
        }

        glanceManager.restoreSession(snapshot.glanceSession, in: windowState)
        floatingBarSanitizer.sanitizeFloatingBarState(in: windowState)
    }
}
