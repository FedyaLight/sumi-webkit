import Foundation
import SumiDomain

@MainActor
extension SidebarSplitCommands {
    init(
        services: SplitShortcutServices,
        splitGroup: @escaping (UUID) -> SplitGroup?,
        windowState: @escaping (UUID) -> BrowserWindowState?,
        liveTab: @escaping (SplitMemberID, BrowserWindowState) -> Tab?,
        closeTab: @escaping (Tab, BrowserWindowState) -> Void
    ) {
        focusGroup = { [focus = services.focus] groupID, memberID, windowID in
            guard let group = splitGroup(groupID),
                  memberID.map(group.contains) ?? true,
                  let windowState = windowState(windowID) else {
                return
            }
            focus.focusSplitGroup(
                group,
                preferredMemberID: memberID,
                in: windowState
            )
        }
        restoreMember = {
            [restoration = services.memberRestoration]
            groupID,
            memberID,
            windowID in
            guard let group = splitGroup(groupID),
                  group.contains(memberID),
                  let windowState = windowState(windowID) else {
                return
            }
            _ = restoration.restoreShortcutSplitMember(
                memberID,
                from: group,
                in: windowState
            )
        }
        closeMember = { groupID, memberID, windowID in
            guard let group = splitGroup(groupID),
                  group.contains(memberID),
                  let windowState = windowState(windowID),
                  let tab = liveTab(memberID, windowState) else {
                return
            }
            closeTab(tab, windowState)
        }
    }
}
