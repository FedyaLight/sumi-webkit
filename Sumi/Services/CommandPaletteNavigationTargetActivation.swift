import Foundation

/// Routes a command-palette navigation target to the role that can activate it.
@MainActor
final class CommandPaletteNavigationTargetActivation {
    private let shortcuts: CommandPaletteShortcutActivation
    private let splitGroups: CommandPaletteSplitGroupActivation

    init(
        shortcuts: CommandPaletteShortcutActivation,
        splitGroups: CommandPaletteSplitGroupActivation
    ) {
        self.shortcuts = shortcuts
        self.splitGroups = splitGroups
    }

    func activate(
        _ identity: CommandPaletteNavigationTargetPresentation.Identity,
        in window: BrowserWindowState
    ) -> Bool {
        switch identity {
        case .shortcut(let pinID):
            return shortcuts.activate(pinID: pinID, in: window)
        case .splitGroup(let groupID):
            return splitGroups.activate(groupID: groupID, in: window)
        }
    }
}
