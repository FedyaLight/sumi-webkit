import Foundation
import SumiDomain

struct SplitShortcutMemberResolution {
    let member: SplitMember
}

/// Resolves an exact durable shortcut member without accepting live-tab IDs.
@MainActor
enum SplitShortcutMemberResolver {
    static func resolve(
        memberID: SplitMemberID,
        in group: SumiDomain.SplitGroup,
        windowState: BrowserWindowState,
        pins: ShortcutPinCollectionStateOwner
    ) -> SplitShortcutMemberResolution? {
        guard case .shortcutPin(let pinID) = memberID,
              let member = group.member(for: memberID),
              pins.shortcutPin(by: pinID) != nil else {
            return nil
        }
        return SplitShortcutMemberResolution(member: member)
    }
}
