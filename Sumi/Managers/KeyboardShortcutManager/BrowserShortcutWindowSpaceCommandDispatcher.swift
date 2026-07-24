import SumiDomain

@MainActor
final class BrowserShortcutWindowSpaceCommandDispatcher {
    private let windows: BrowserWindowCommands
    private let dialogs: BrowserNativeDialogPresentationOwner
    private let recovery: BrowserSessionRecoveryCommands
    private let spaces: BrowserKeyboardSpaceCommands

    init(
        windows: BrowserWindowCommands,
        dialogs: BrowserNativeDialogPresentationOwner,
        recovery: BrowserSessionRecoveryCommands,
        spaces: BrowserKeyboardSpaceCommands
    ) {
        self.windows = windows
        self.dialogs = dialogs
        self.recovery = recovery
        self.spaces = spaces
    }

    func dispatch(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        let windowState = context.windowState
        switch action {
        case .undoCloseTab:
            recovery.reopenMostRecentClosedItem(in: windowState)
        case .nextSpace:
            spaces.selectRelativeSpace(offset: 1, in: windowState)
        case .previousSpace:
            spaces.selectRelativeSpace(offset: -1, in: windowState)
        case .closeWindow:
            windows.closeWindow(windowState)
        case .toggleFullScreen:
            windows.toggleFullScreen(windowState)
        case .expandAllFolders:
            spaces.expandAllFolders(in: windowState)
        default:
            guard let index = SpaceSwitchShortcuts.spaceIndex(for: action) else {
                return false
            }
            spaces.selectSpace(atIndex: index, in: windowState)
        }
        return true
    }

    func canDispatch(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        switch action {
        case .nextSpace, .previousSpace:
            return spaces.canSelectRelativeSpace(in: context.windowState)
        case .goToSpace1, .goToSpace2, .goToSpace3, .goToSpace4,
             .goToSpace5, .goToSpace6, .goToSpace7, .goToSpace8,
             .goToSpace9, .goToSpace10:
            guard let index = SpaceSwitchShortcuts.spaceIndex(for: action)
            else { return false }
            return spaces.canSelectSpace(
                atIndex: index,
                in: context.windowState
            )
        case .expandAllFolders:
            return context.windowState.currentSpaceId != nil
        case .undoCloseTab, .closeWindow, .toggleFullScreen:
            return true
        default:
            return false
        }
    }

    func dispatchApplicationAction(_ action: ShortcutAction) -> Bool {
        switch action {
        case .newWindow:
            windows.createNewWindow()
        case .newPrivateWindow:
            windows.createIncognitoWindow()
        case .closeBrowser:
            dialogs.showQuitDialog()
        default:
            return false
        }
        return true
    }
}
