import Foundation
import SumiDomain

@MainActor
struct WindowSessionSplitRestorer {
    let tabManager: TabManager
    let focus: any WindowSessionSplitFocusing

    func restorePendingSelectionIfNeeded(
        in windowState: BrowserWindowState
    ) {
        restoreLegacyGroupIfNeeded(in: windowState)
        guard let pending = windowState.restorationState.pendingSplitSelection else {
            return
        }
        guard let group = tabManager.splitGroupStore.group(id: pending.groupID) else {
            if tabManager.startupRestoreLifecycle.hasLoadedInitialData {
                windowState.restorationState.pendingSplitSelection = nil
            }
            return
        }

        windowState.restorationState.pendingSplitSelection = nil
        focus.focusSplitGroup(
            group,
            preferredMemberID: resolvedPreferredMember(
                pending.preferredMemberID,
                in: group,
                windowState: windowState
            ),
            in: windowState
        )
    }

    private func restoreLegacyGroupIfNeeded(
        in windowState: BrowserWindowState
    ) {
        guard let group = windowState.restorationState.pendingLegacySplitGroup,
              tabManager.startupRestoreLifecycle.hasLoadedInitialData else {
            return
        }

        guard group.memberIDs.allSatisfy({ memberID in
            guard case .regularTab(let tabID) = memberID else { return false }
            return tabManager.tabCollectionMembershipOwner.tab(for: tabID) != nil
        }) else {
            windowState.restorationState.pendingLegacySplitGroup = nil
            if windowState.restorationState.pendingSplitSelection?.groupID == group.id {
                windowState.restorationState.pendingSplitSelection = nil
            }
            return
        }

        guard tabManager.splitGroupMutations.insert(group) else {
            windowState.restorationState.pendingLegacySplitGroup = nil
            if tabManager.splitGroupStore.group(id: group.id) == nil,
               windowState.restorationState.pendingSplitSelection?.groupID == group.id {
                windowState.restorationState.pendingSplitSelection = nil
            }
            return
        }
        windowState.restorationState.pendingLegacySplitGroup = nil
    }

    private func resolvedPreferredMember(
        _ persistedMemberID: SplitMemberID?,
        in group: SumiDomain.SplitGroup,
        windowState: BrowserWindowState
    ) -> SplitMemberID? {
        if let persistedMemberID, group.contains(persistedMemberID) {
            return persistedMemberID
        }
        if let pinID = windowState.currentShortcutPinId {
            let memberID = SplitMemberID.shortcutPin(pinID)
            if group.contains(memberID) { return memberID }
        }
        if let tabID = windowState.currentTabId {
            let memberID = SplitMemberID.regularTab(tabID)
            if group.contains(memberID) { return memberID }
        }
        return group.memberIDs.first
    }
}
