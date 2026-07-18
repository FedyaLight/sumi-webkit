import SumiDomain

@MainActor
final class BrowserShortcutChromeCommandDispatcher {
    private let chrome: BrowserChromeCommands
    private let theme: BrowserWorkspaceThemeEditorOwner
    private let sidebar: BrowserSidebarPresentationOwner
    private let reader: BrowserKeyboardReaderCommands

    init(
        chrome: BrowserChromeCommands,
        theme: BrowserWorkspaceThemeEditorOwner,
        sidebar: BrowserSidebarPresentationOwner,
        reader: BrowserKeyboardReaderCommands
    ) {
        self.chrome = chrome
        self.theme = theme
        self.sidebar = sidebar
        self.reader = reader
    }

    func dispatch(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        switch action {
        case .viewDownloads:
            chrome.toggleDownloadsPopover(in: context.windowState)
        case .toggleSidebar:
            sidebar.toggleSidebar(for: context.windowState)
        case .toggleReaderMode:
            reader.toggleReaderMode(on: context.page)
        case .customizeSpaceGradient:
            theme.showGradientEditor(in: context.windowState)
        default:
            return false
        }
        return true
    }
}
