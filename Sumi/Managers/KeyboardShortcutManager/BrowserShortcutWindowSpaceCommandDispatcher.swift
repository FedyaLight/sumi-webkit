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

    func dispatch(_ action: ShortcutAction) -> Bool {
        switch action {
        case .undoCloseTab:
            recovery.reopenMostRecentClosedItem()
        case .nextSpace:
            spaces.selectRelativeSpace(offset: 1)
        case .previousSpace:
            spaces.selectRelativeSpace(offset: -1)
        case .newWindow:
            windows.createNewWindow()
        case .closeWindow:
            windows.closeActiveWindow()
        case .closeBrowser:
            dialogs.showQuitDialog()
        case .toggleFullScreen:
            windows.toggleFullScreenForActiveWindow()
        case .expandAllFolders:
            spaces.expandAllFoldersInActiveSpace()
        default:
            return false
        }
        return true
    }
}
