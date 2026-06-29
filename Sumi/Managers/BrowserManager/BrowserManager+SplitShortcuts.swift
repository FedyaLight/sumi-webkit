import Foundation

@MainActor
extension BrowserManager {
    func focusSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        sidebarSplitShortcutRoutingOwner.focusSplitGroup(group, in: windowState)
    }

    func completePendingSplitGroupFocusIfReady(in windowState: BrowserWindowState, spaceId: UUID) {
        sidebarSplitShortcutRoutingOwner.completePendingSplitGroupFocusIfReady(
            in: windowState,
            spaceId: spaceId
        )
    }

    func restoreShortcutSplitMember(
        _ itemId: UUID,
        from group: SplitGroup,
        in windowState: BrowserWindowState,
        preserveLiveInstance: Bool = true
    ) {
        sidebarSplitShortcutRoutingOwner.restoreShortcutSplitMember(
            itemId,
            from: group,
            in: windowState,
            preserveLiveInstance: preserveLiveInstance
        )
    }

    func unloadShortcutHostedSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        sidebarSplitShortcutRoutingOwner.unloadShortcutHostedSplitGroup(group, in: windowState)
    }
}
