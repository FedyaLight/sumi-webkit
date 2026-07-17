import Foundation
import SumiDomain

@MainActor
final class SidebarSplitCloseCommand {
    private let groups: SplitGroupStore
    private let windows: SidebarWindowIdentityQuery
    private let membership: TabCollectionMembershipOwner
    private let shortcuts: TabShortcutPresentationOwner
    private let close: BrowserTabCloseOrchestrationOwner

    init(
        groups: SplitGroupStore,
        windows: SidebarWindowIdentityQuery,
        membership: TabCollectionMembershipOwner,
        shortcuts: TabShortcutPresentationOwner,
        close: BrowserTabCloseOrchestrationOwner
    ) {
        self.groups = groups
        self.windows = windows
        self.membership = membership
        self.shortcuts = shortcuts
        self.close = close
    }

    func closeMember(_ groupID: UUID, _ memberID: SplitMemberID, _ windowID: UUID) {
        guard let group = groups.group(id: groupID),
              group.contains(memberID),
              let windowState = windows.window(id: windowID),
              let tab = liveTab(for: memberID, in: windowState) else {
            return
        }
        close.closeTab(tab, in: windowState)
    }

    private func liveTab(
        for memberID: SplitMemberID,
        in windowState: BrowserWindowState
    ) -> Tab? {
        switch memberID {
        case .regularTab(let tabID):
            membership.tab(for: tabID)
        case .shortcutPin(let pinID):
            shortcuts.shortcutLiveTab(for: pinID, in: windowState.id)
        }
    }
}
