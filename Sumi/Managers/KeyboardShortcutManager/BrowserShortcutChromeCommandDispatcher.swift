import SumiDomain

@MainActor
final class BrowserShortcutChromeCommandDispatcher {
    private let chrome: BrowserChromeCommands
    private let theme: BrowserWorkspaceThemeEditorOwner
    private let sidebar: BrowserShortcutSidebarCommands
    private let reader: BrowserKeyboardReaderCommands
    private let settings: BrowserShortcutSettingsCommands

    init(
        chrome: BrowserChromeCommands,
        theme: BrowserWorkspaceThemeEditorOwner,
        sidebar: BrowserShortcutSidebarCommands,
        reader: BrowserKeyboardReaderCommands,
        settings: BrowserShortcutSettingsCommands
    ) {
        self.chrome = chrome
        self.theme = theme
        self.sidebar = sidebar
        self.reader = reader
        self.settings = settings
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
        case .newFolder:
            sidebar.createFolderInCurrentSpace(in: context.windowState)
        case .openSettings:
            settings.openSettings(
                selecting: .general,
                in: context.windowState
            )
        case .manageExtensions:
            settings.openSettings(
                selecting: .extensions,
                in: context.windowState
            )
        case .toggleTabsOnRight:
            return settings.toggleTabsOnRight()
        case .switchToAutomaticAppearance:
            return settings.applyWindowScheme(.auto)
        case .switchToLightMode:
            return settings.applyWindowScheme(.light)
        case .switchToDarkMode:
            return settings.applyWindowScheme(.dark)
        default:
            return false
        }
        return true
    }

    func canDispatch(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        return switch action {
        case .viewDownloads, .toggleSidebar, .customizeSpaceGradient,
             .openSettings, .manageExtensions:
            true
        case .newFolder:
            sidebar.canCreateFolderInCurrentSpace(in: context.windowState)
        case .toggleTabsOnRight:
            settings.isAttached
        case .switchToAutomaticAppearance:
            settings.canApplyWindowScheme(.auto)
        case .switchToLightMode:
            settings.canApplyWindowScheme(.light)
        case .switchToDarkMode:
            settings.canApplyWindowScheme(.dark)
        case .toggleReaderMode:
            context.page != nil
        default:
            false
        }
    }
}
