import Foundation
import SumiDomain

@MainActor
final class SidebarSplitFocusCommands {
    private let focus: SplitShortcutFocusService
    private let restoration: SplitShortcutMemberRestoreService
    private let groups: SplitGroupStore
    private let windows: SidebarWindowIdentityQuery

    init(
        focus: SplitShortcutFocusService,
        restoration: SplitShortcutMemberRestoreService,
        groups: SplitGroupStore,
        windows: SidebarWindowIdentityQuery
    ) {
        self.focus = focus
        self.restoration = restoration
        self.groups = groups
        self.windows = windows
    }

    func focusGroup(_ groupID: UUID, _ memberID: SplitMemberID?, _ windowID: UUID) {
        guard let group = groups.group(id: groupID),
              memberID.map(group.contains) ?? true,
              let windowState = windows.window(id: windowID) else {
            return
        }
        focus.focusSplitGroup(
            group,
            preferredMemberID: memberID,
            in: windowState
        )
    }

    func restoreMember(_ groupID: UUID, _ memberID: SplitMemberID, _ windowID: UUID) {
        guard let group = groups.group(id: groupID),
              group.contains(memberID),
              let windowState = windows.window(id: windowID) else {
            return
        }
        _ = restoration.restoreShortcutSplitMember(
            memberID,
            from: group,
            in: windowState
        )
    }
}
