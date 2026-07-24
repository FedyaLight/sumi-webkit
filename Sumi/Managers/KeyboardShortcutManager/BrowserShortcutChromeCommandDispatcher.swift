import SumiDomain

@MainActor
final class BrowserShortcutChromeCommandDispatcher {
    private let chrome: BrowserChromeCommands
    private let theme: BrowserWorkspaceThemeEditorOwner
    private let sidebar: BrowserSidebarPresentationOwner
    private let reader: BrowserKeyboardReaderCommands
    private let folderActions: BrowserSidebarActionOwner
    private let settings: BrowserSettingsNavigationService
    private let settingsAttachment: BrowserSettingsAttachmentCoordinator

    init(
        chrome: BrowserChromeCommands,
        theme: BrowserWorkspaceThemeEditorOwner,
        sidebar: BrowserSidebarPresentationOwner,
        reader: BrowserKeyboardReaderCommands,
        folderActions: BrowserSidebarActionOwner,
        settings: BrowserSettingsNavigationService,
        settingsAttachment: BrowserSettingsAttachmentCoordinator
    ) {
        self.chrome = chrome
        self.theme = theme
        self.sidebar = sidebar
        self.reader = reader
        self.folderActions = folderActions
        self.settings = settings
        self.settingsAttachment = settingsAttachment
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
            folderActions.createFolderInCurrentSpace(
                in: context.windowState
            )
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
            guard let settings = settingsAttachment.settings else {
                return false
            }
            settings.sidebarPosition =
                settings.sidebarPosition == .left ? .right : .left
        case .switchToAutomaticAppearance:
            guard let settings = settingsAttachment.settings else {
                return false
            }
            settings.windowSchemeMode = .auto
        case .switchToLightMode:
            guard let settings = settingsAttachment.settings else {
                return false
            }
            settings.windowSchemeMode = .light
        case .switchToDarkMode:
            guard let settings = settingsAttachment.settings else {
                return false
            }
            settings.windowSchemeMode = .dark
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
            folderActions.canCreateFolderInCurrentSpace(
                in: context.windowState
            )
        case .toggleTabsOnRight:
            settingsAttachment.settings != nil
        case .switchToAutomaticAppearance:
            settingsAttachment.settings.map {
                $0.windowSchemeMode != .auto
            } ?? false
        case .switchToLightMode:
            settingsAttachment.settings.map {
                $0.windowSchemeMode != .light
            } ?? false
        case .switchToDarkMode:
            settingsAttachment.settings.map {
                $0.windowSchemeMode != .dark
            } ?? false
        case .toggleReaderMode:
            context.page != nil
        default:
            false
        }
    }
}
