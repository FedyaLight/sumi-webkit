import Foundation
import SumiDomain

struct SplitShortcutMemberResolution {
    let member: SplitMember
    let restoredLiveTab: Tab?
}

/// Resolves an exact durable shortcut member without accepting live-tab IDs.
@MainActor
enum SplitShortcutMemberResolver {
    static func resolve(
        memberID: SplitMemberID,
        in group: SumiDomain.SplitGroup,
        windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> SplitShortcutMemberResolution? {
        guard case .shortcutPin(let pinID) = memberID,
              let member = group.member(for: memberID),
              tabManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pinID) != nil else {
            return nil
        }
        return SplitShortcutMemberResolution(
            member: member,
            restoredLiveTab: tabManager.shortcutPresentationOwner
                .shortcutLiveTab(for: pinID, in: windowState.id)
        )
    }
}
