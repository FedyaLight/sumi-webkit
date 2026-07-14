import Foundation
import SumiDomain

@MainActor
struct WindowSessionSnapshotApplier {
    let glanceManager: GlanceManager

    func apply(
        _ snapshot: WindowSessionSnapshot,
        to windowState: BrowserWindowState
    ) {
        applyPersistedFields(snapshot, to: windowState)
        glanceManager.restoreSession(snapshot.glanceSession, in: windowState)
    }

    /// Applies the archived model before a shell is published. Runtime-backed
    /// Glance restoration waits until the state has entered WindowRegistry.
    func prepareForRegistration(
        _ snapshot: WindowSessionSnapshot,
        to windowState: BrowserWindowState
    ) {
        applyPersistedFields(snapshot, to: windowState)
    }

    private func applyPersistedFields(
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
        windowState.presentationState.isDownloadsPopoverPresented = false
        windowState.floatingBarDraftText = snapshot.floatingBarDraft.text
        windowState.floatingBarDraftNavigatesCurrentTab = snapshot
            .floatingBarDraft.navigateCurrentTab

        windowState.splitSelection = nil
        if let selection = snapshot.splitSelection {
            windowState.restorationState.pendingLegacySplitGroup = nil
            windowState.restorationState.pendingSplitSelection = PendingWindowSplitSelection(
                groupID: selection.groupID,
                preferredMemberID: selection.activeMemberID
            )
            return
        }

        if let migration = snapshot.legacySplitSessionForMigration?
            .makeSplitMigration(spaceId: snapshot.currentSpaceId) {
            windowState.restorationState.pendingLegacySplitGroup = migration.group
            windowState.restorationState.pendingSplitSelection = PendingWindowSplitSelection(
                groupID: migration.group.id,
                preferredMemberID: migration.preferredMemberID
            )
            return
        }

        windowState.restorationState.pendingLegacySplitGroup = nil
        windowState.restorationState.pendingSplitSelection = snapshot
            .legacyActiveSplitGroupID.map { groupID in
                PendingWindowSplitSelection(
                    groupID: groupID,
                    preferredMemberID: snapshot.activeShortcutPinId
                        .map(SplitMemberID.shortcutPin)
                        ?? snapshot.currentTabId.map(SplitMemberID.regularTab)
                )
            }
    }
}
