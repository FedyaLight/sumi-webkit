import Foundation
import SumiDomain

@MainActor
final class SidebarSplitFocusCommands {
    private let focus: SplitShortcutFocusService
    private let groups: SplitGroupStore
    private let windows: SidebarWindowIdentityQuery

    init(
        focus: SplitShortcutFocusService,
        groups: SplitGroupStore,
        windows: SidebarWindowIdentityQuery
    ) {
        self.focus = focus
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

}
