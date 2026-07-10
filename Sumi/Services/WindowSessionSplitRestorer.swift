import Foundation

@MainActor
struct WindowSessionSplitRestorer {
    let tabManager: TabManager
    let focus: any WindowSessionSplitFocusing

    func restorePendingSelectionIfNeeded(
        in windowState: BrowserWindowState
    ) {
        restoreLegacyGroupIfNeeded(in: windowState)
        guard let groupId = windowState.pendingSessionSplitGroupId else {
            return
        }
        guard let group = tabManager.splitGroupCollectionStateOwner
            .group(with: groupId) else {
            if tabManager.startupRestoreLifecycle.hasLoadedInitialData {
                windowState.pendingSessionSplitGroupId = nil
            }
            return
        }

        windowState.pendingSessionSplitGroupId = nil
        focus.focusSplitGroup(group, in: windowState)
    }

    private func restoreLegacyGroupIfNeeded(
        in windowState: BrowserWindowState
    ) {
        guard let group = windowState.pendingSessionLegacySplitGroup,
              tabManager.startupRestoreLifecycle.hasLoadedInitialData else {
            return
        }

        guard group.tabIds.allSatisfy({
            tabManager.tabCollectionMembershipOwner.tab(for: $0) != nil
        }) else {
            windowState.pendingSessionLegacySplitGroup = nil
            if windowState.pendingSessionSplitGroupId == group.id {
                windowState.pendingSessionSplitGroupId = nil
            }
            return
        }

        tabManager.splitGroupStructureOwner.upsertSplitGroup(group)
        windowState.pendingSessionLegacySplitGroup = nil
    }
}
