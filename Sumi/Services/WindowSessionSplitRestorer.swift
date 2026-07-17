import Foundation
import SumiDomain

@MainActor
struct WindowSessionSplitRestorer {
    let groups: SplitGroupStore
    let startupRestore: TabStartupRestoreLifecycle
    let focus: any WindowSessionSplitFocusing

    func restorePendingSelectionIfNeeded(
        in windowState: BrowserWindowState
    ) {
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
