import Foundation

@MainActor
extension BrowserManager {
    func focusSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        sidebarCommandService.splitShortcutRouting.focusSplitGroup(group, in: windowState)
    }

    func completePendingSplitGroupFocusIfReady(in windowState: BrowserWindowState, spaceId: UUID) {
        sidebarCommandService.splitShortcutRouting.completePendingSplitGroupFocusIfReady(
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
        sidebarCommandService.splitShortcutRouting.restoreShortcutSplitMember(
            itemId,
            from: group,
            in: windowState,
            preserveLiveInstance: preserveLiveInstance
        )
    }

    func unloadShortcutHostedSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        sidebarCommandService.splitShortcutRouting.unloadShortcutHostedSplitGroup(group, in: windowState)
    }
}
