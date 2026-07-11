import Foundation

/// The two split-shortcut commands exposed to sidebar views.
@MainActor
struct SidebarSplitShortcutCommands {
    let focusGroup: (SplitGroup, BrowserWindowState) -> Void
    let restoreMember: (UUID, SplitGroup, BrowserWindowState) -> Void

    init(services: SplitShortcutServices) {
        focusGroup = { [focus = services.focus] group, windowState in
            focus.focusSplitGroup(group, in: windowState)
        }
        restoreMember = { [restoration = services.memberRestoration] itemId, group, windowState in
            _ = restoration.restoreShortcutSplitMember(
                itemId,
                from: group,
                in: windowState
            )
        }
    }

    init(
        focusGroup: @escaping (SplitGroup, BrowserWindowState) -> Void,
        restoreMember: @escaping (UUID, SplitGroup, BrowserWindowState) -> Void
    ) {
        self.focusGroup = focusGroup
        self.restoreMember = restoreMember
    }
}
