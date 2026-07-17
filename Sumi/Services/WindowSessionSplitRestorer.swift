import Foundation
import SumiDomain

@MainActor
struct WindowSessionSplitRestorer {
    let groups: SplitGroupStore
    let mutations: SplitGroupMutationService
    let membership: TabCollectionMembershipOwner
    let startupRestore: TabStartupRestoreLifecycle
    let focus: any WindowSessionSplitFocusing

    func restorePendingSelectionIfNeeded(
        in windowState: BrowserWindowState
    ) {
        restoreLegacyGroupIfNeeded(in: windowState)
        guard let pending = windowState.restorationState.pendingSplitSelection else {
            return
        }
        guard let group = groups.group(id: pending.groupID) else {
            if startupRestore.hasLoadedInitialData {
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
              startupRestore.hasLoadedInitialData else {
            return
        }

        guard group.memberIDs.allSatisfy({ memberID in
            guard case .regularTab(let tabID) = memberID else { return false }
            return membership.tab(for: tabID) != nil
        }) else {
            windowState.restorationState.pendingLegacySplitGroup = nil
            if windowState.restorationState.pendingSplitSelection?.groupID == group.id {
                windowState.restorationState.pendingSplitSelection = nil
            }
            return
        }

        guard mutations.insert(group) else {
            windowState.restorationState.pendingLegacySplitGroup = nil
            if groups.group(id: group.id) == nil,
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
