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

    func dispatch(_ action: ShortcutAction) -> Bool {
        switch action {
        case .viewDownloads:
            chrome.showDownloads()
        case .toggleSidebar:
            sidebar.toggleSidebar()
        case .toggleReaderMode:
            reader.toggleReaderModeInActiveWindow()
        case .customizeSpaceGradient:
            theme.showGradientEditor()
        default:
            return false
        }
        return true
    }
}
