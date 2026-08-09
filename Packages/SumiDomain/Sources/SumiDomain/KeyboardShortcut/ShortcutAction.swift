import Foundation

public enum ShortcutAction: String, CaseIterable, Hashable, Codable, Sendable {
    case goBack = "go_back"
    case goForward = "go_forward"
    case refresh = "refresh"
    case clearCookiesAndRefresh = "clear_cookies_and_refresh"

    case newTab = "new_tab"
    case closeTab = "close_tab"
    case undoCloseTab = "undo_close_tab"
    case nextTab = "next_tab"
    case previousTab = "previous_tab"
    case goToTab1 = "go_to_tab_1"
    case goToTab2 = "go_to_tab_2"
    case goToTab3 = "go_to_tab_3"
    case goToTab4 = "go_to_tab_4"
    case goToTab5 = "go_to_tab_5"
    case goToTab6 = "go_to_tab_6"
    case goToTab7 = "go_to_tab_7"
    case goToTab8 = "go_to_tab_8"
    case goToLastTab = "go_to_last_tab"
    case duplicateTab = "duplicate_tab"
    case splitGrid = "split_grid"
    case splitVertical = "split_vertical"
    case splitHorizontal = "split_horizontal"
    case unsplit = "unsplit"
    case newEmptySplit = "new_empty_split"
    case addSplitTop = "add_split_top"
    case addSplitLeft = "add_split_left"
    case addSplitRight = "add_split_right"
    case addSplitBottom = "add_split_bottom"
    case newFolder = "new_folder"
    case pinTab = "pin_tab"
    case unpinTab = "unpin_tab"
    case addToFavorite = "add_to_favorite"
    case removeFromFavorite = "remove_from_favorite"
    case newBoost = "new_boost"

    case nextSpace = "next_space"
    case previousSpace = "previous_space"
    case goToSpace1 = "go_to_space_1"
    case goToSpace2 = "go_to_space_2"
    case goToSpace3 = "go_to_space_3"
    case goToSpace4 = "go_to_space_4"
    case goToSpace5 = "go_to_space_5"
    case goToSpace6 = "go_to_space_6"
    case goToSpace7 = "go_to_space_7"
    case goToSpace8 = "go_to_space_8"
    case goToSpace9 = "go_to_space_9"
    case goToSpace10 = "go_to_space_10"

    case newWindow = "new_window"
    case newPrivateWindow = "new_private_window"
    case closeWindow = "close_window"
    case closeBrowser = "close_browser"
    case toggleFullScreen = "toggle_full_screen"

    case openDevTools = "open_dev_tools"
    case viewDownloads = "view_downloads"
    case viewHistory = "view_history"
    case openSettings = "open_settings"
    case manageExtensions = "manage_extensions"
    case printPage = "print_page"
    case captureScreenshot = "capture_screenshot"
    case expandAllFolders = "expand_all_folders"
    case focusAddressBar = "focus_address_bar"
    case findInPage = "find_in_page"
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case actualSize = "actual_size"
    case toggleSidebar = "toggle_sidebar"
    case copyCurrentURL = "copy_current_url"
    case hardReload = "hard_reload"
    case toggleReaderMode = "toggle_reader_mode"
    case muteUnmuteAudio = "mute_unmute_audio"
    case customizeSpaceGradient = "customize_space_gradient"
    case toggleTabsOnRight = "toggle_tabs_on_right"
    case switchToAutomaticAppearance = "switch_to_automatic_appearance"
    case switchToLightMode = "switch_to_light_mode"
    case switchToDarkMode = "switch_to_dark_mode"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let normalizedValue: String
        switch value {
        case "add_to_essentials": normalizedValue = "add_to_favorite"
        case "remove_from_essentials": normalizedValue = "remove_from_favorite"
        default: normalizedValue = value
        }
        guard let action = Self(rawValue: normalizedValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported shortcut action: \(value)"
            )
        }
        self = action
    }

    public var displayName: String {
        switch self {
        case .goBack: return "Go Back"
        case .goForward: return "Go Forward"
        case .refresh: return "Refresh"
        case .clearCookiesAndRefresh: return "Clear Cookies and Refresh"
        case .newTab: return "New Tab"
        case .closeTab: return "Close Tab"
        case .undoCloseTab: return "Undo Close Tab"
        case .nextTab: return "Next Tab"
        case .previousTab: return "Previous Tab"
        case .goToTab1: return "Go to Tab 1"
        case .goToTab2: return "Go to Tab 2"
        case .goToTab3: return "Go to Tab 3"
        case .goToTab4: return "Go to Tab 4"
        case .goToTab5: return "Go to Tab 5"
        case .goToTab6: return "Go to Tab 6"
        case .goToTab7: return "Go to Tab 7"
        case .goToTab8: return "Go to Tab 8"
        case .goToLastTab: return "Go to Last Tab"
        case .duplicateTab: return "Duplicate Tab"
        case .splitGrid: return "Split Grid"
        case .splitVertical: return "Split Vertical"
        case .splitHorizontal: return "Split Horizontal"
        case .unsplit: return "Unsplit"
        case .newEmptySplit: return "New Empty Split"
        case .addSplitTop: return "Add Top Split"
        case .addSplitLeft: return "Add Left Split"
        case .addSplitRight: return "Add Right Split"
        case .addSplitBottom: return "Add Bottom Split"
        case .newFolder: return "New Folder"
        case .pinTab: return "Pin Tab"
        case .unpinTab: return "Unpin Tab"
        case .addToFavorite: return "Add to Favorite"
        case .removeFromFavorite: return "Remove from Favorite"
        case .newBoost: return "New Boost"
        case .nextSpace: return "Next Space"
        case .previousSpace: return "Previous Space"
        case .goToSpace1: return "Go to Space 1"
        case .goToSpace2: return "Go to Space 2"
        case .goToSpace3: return "Go to Space 3"
        case .goToSpace4: return "Go to Space 4"
        case .goToSpace5: return "Go to Space 5"
        case .goToSpace6: return "Go to Space 6"
        case .goToSpace7: return "Go to Space 7"
        case .goToSpace8: return "Go to Space 8"
        case .goToSpace9: return "Go to Space 9"
        case .goToSpace10: return "Go to Space 10"
        case .newWindow: return "New Window"
        case .newPrivateWindow: return "New Private Window"
        case .closeWindow: return "Close Window"
        case .closeBrowser: return "Close Browser"
        case .toggleFullScreen: return "Toggle Full Screen"
        case .openDevTools: return "Developer Tools"
        case .viewDownloads: return "View Downloads"
        case .viewHistory: return "View History"
        case .openSettings: return "Settings"
        case .manageExtensions: return "Manage Extensions"
        case .printPage: return "Print"
        case .captureScreenshot: return "Capture Screenshot"
        case .expandAllFolders: return "Expand All Folders"
        case .focusAddressBar: return "Focus Address Bar"
        case .findInPage: return "Find in Page"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .actualSize: return "Actual Size"
        case .toggleSidebar: return "Toggle Sidebar"
        case .copyCurrentURL: return "Copy Current URL"
        case .hardReload: return "Hard Reload"
        case .toggleReaderMode: return "Toggle Reader Mode"
        case .muteUnmuteAudio: return "Mute/Unmute Audio"
        case .customizeSpaceGradient: return "Customize Space Gradient"
        case .toggleTabsOnRight: return "Toggle Tabs on Right"
        case .switchToAutomaticAppearance: return "Switch to Automatic Appearance"
        case .switchToLightMode: return "Switch to Light Mode"
        case .switchToDarkMode: return "Switch to Dark Mode"
        }
    }

    /// User-facing title in the command catalog. Shortcut settings keep the
    /// shorter input-oriented names above, while the palette follows the
    /// wording used by Arc and Zen.
    public var commandPaletteTitle: String {
        switch self {
        case .refresh: return "Reload Tab"
        case .duplicateTab: return "Duplicate Current Tab"
        case .splitVertical: return "Add Vertical Split View"
        case .splitHorizontal: return "Add Horizontal Split View"
        case .unsplit: return "Close Split View Pane"
        case .newEmptySplit: return "Add Split View"
        case .closeBrowser: return "Quit Sumi"
        case .actualSize: return "Reset Zoom"
        case .hardReload: return "Reload Tab Without Cache"
        case .customizeSpaceGradient: return "Open Theme Picker"
        default: return displayName
        }
    }

    /// Explicit template order for Actions mode. The leading section follows
    /// Zen's readable global-action catalog; Arc-only browser commands follow
    /// in the order users encounter their native menu groups.
    public static let commandPaletteCatalogOrder: [ShortcutAction] = [
        .toggleSidebar,
        .customizeSpaceGradient,
        .newEmptySplit,
        .newFolder,
        .copyCurrentURL,
        .openSettings,
        .newPrivateWindow,
        .newWindow,
        .pinTab,
        .unpinTab,
        .newBoost,
        .nextSpace,
        .previousSpace,
        .closeTab,
        .refresh,
        .hardReload,
        .nextTab,
        .previousTab,
        .captureScreenshot,
        .toggleTabsOnRight,
        .addToFavorite,
        .removeFromFavorite,
        .findInPage,
        .manageExtensions,
        .switchToAutomaticAppearance,
        .switchToLightMode,
        .switchToDarkMode,
        .printPage,
        .addSplitTop,
        .addSplitLeft,
        .addSplitRight,
        .addSplitBottom,
        .unsplit,
        .goBack,
        .goForward,
        .clearCookiesAndRefresh,
        .duplicateTab,
        .closeWindow,
        .closeBrowser,
        .toggleFullScreen,
        .openDevTools,
        .viewDownloads,
        .viewHistory,
        .expandAllFolders,
        .zoomIn,
        .zoomOut,
        .actualSize,
    ]

    public var category: ShortcutCategory {
        switch self {
        case .goBack, .goForward, .refresh, .clearCookiesAndRefresh, .focusAddressBar, .findInPage, .hardReload, .toggleReaderMode, .newBoost:
            return .navigation
        case .newTab, .closeTab, .undoCloseTab, .nextTab, .previousTab, .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8, .goToLastTab, .duplicateTab, .splitGrid, .splitVertical, .splitHorizontal, .unsplit, .newEmptySplit, .addSplitTop, .addSplitLeft, .addSplitRight, .addSplitBottom, .pinTab, .unpinTab, .addToFavorite, .removeFromFavorite:
            return .tabs
        case .newFolder, .nextSpace, .previousSpace, .customizeSpaceGradient,
             .goToSpace1, .goToSpace2, .goToSpace3, .goToSpace4, .goToSpace5,
             .goToSpace6, .goToSpace7, .goToSpace8, .goToSpace9, .goToSpace10:
            return .spaces
        case .newWindow, .newPrivateWindow, .closeWindow, .closeBrowser,
             .toggleFullScreen, .toggleSidebar, .toggleTabsOnRight,
             .switchToAutomaticAppearance, .switchToLightMode,
             .switchToDarkMode:
            return .window
        case .openDevTools, .viewDownloads, .viewHistory, .openSettings,
             .manageExtensions, .printPage, .captureScreenshot, .expandAllFolders, .zoomIn,
             .zoomOut, .actualSize, .copyCurrentURL, .muteUnmuteAudio:
            return .tools
        }
    }

    public var commandPaletteSymbolName: String {
        switch self {
        case .goBack: return "chevron.left"
        case .goForward: return "chevron.right"
        case .refresh: return "arrow.clockwise"
        case .clearCookiesAndRefresh: return "trash.slash"
        case .newTab: return "plus"
        case .closeTab: return "xmark"
        case .undoCloseTab: return "arrow.uturn.backward"
        case .nextTab: return "arrow.right.to.line"
        case .previousTab: return "arrow.left.to.line"
        case .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5,
             .goToTab6, .goToTab7, .goToTab8, .goToLastTab:
            return "rectangle.stack"
        case .duplicateTab: return "plus.square.on.square"
        case .splitGrid: return "rectangle.split.2x2"
        case .splitVertical: return "rectangle.split.2x1"
        case .splitHorizontal: return "rectangle.split.1x2"
        case .unsplit: return "rectangle"
        case .newEmptySplit: return "rectangle.split.2x1"
        case .addSplitTop, .addSplitBottom:
            return "rectangle.split.1x2"
        case .addSplitLeft, .addSplitRight:
            return "rectangle.split.2x1"
        case .newFolder: return "folder.badge.plus"
        case .pinTab: return "pin"
        case .unpinTab: return "pin.slash"
        case .addToFavorite: return "star"
        case .removeFromFavorite: return "star.slash"
        case .newBoost: return "wand.and.stars"
        case .nextSpace: return "arrow.right.circle"
        case .previousSpace: return "arrow.left.circle"
        case .goToSpace1, .goToSpace2, .goToSpace3, .goToSpace4, .goToSpace5,
             .goToSpace6, .goToSpace7, .goToSpace8, .goToSpace9, .goToSpace10:
            return "rectangle.3.group"
        case .newWindow: return "macwindow.badge.plus"
        case .newPrivateWindow: return "eye.slash"
        case .closeWindow: return "macwindow.badge.xmark"
        case .closeBrowser: return "power"
        case .toggleFullScreen: return "arrow.up.left.and.arrow.down.right"
        case .openDevTools: return "hammer"
        case .viewDownloads: return "arrow.down.circle"
        case .viewHistory: return "clock.arrow.circlepath"
        case .openSettings: return "gearshape"
        case .manageExtensions: return "puzzlepiece.extension"
        case .printPage: return "printer"
        case .captureScreenshot: return "camera"
        case .expandAllFolders: return "folder.badge.plus"
        case .focusAddressBar: return "text.cursor"
        case .findInPage: return "doc.text.magnifyingglass"
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .actualSize: return "1.magnifyingglass"
        case .toggleSidebar: return "sidebar.left"
        case .copyCurrentURL: return "link"
        case .hardReload: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .toggleReaderMode: return "text.book.closed"
        case .muteUnmuteAudio: return "speaker.wave.2"
        case .customizeSpaceGradient: return "paintpalette"
        case .toggleTabsOnRight: return "sidebar.right"
        case .switchToAutomaticAppearance: return "sparkles"
        case .switchToLightMode: return "sun.max"
        case .switchToDarkMode: return "moon.stars"
        }
    }

    public var commandPaletteKeywords: [String] {
        switch self {
        case .refresh: return ["reload", "page"]
        case .clearCookiesAndRefresh: return ["reload", "cache", "site data"]
        case .newTab: return ["open tab"]
        case .closeTab: return ["remove tab"]
        case .undoCloseTab: return ["reopen tab", "restore tab"]
        case .duplicateTab: return ["copy tab", "clone tab"]
        case .splitGrid: return ["split view", "four panes"]
        case .splitVertical: return ["split view", "left", "right", "side by side"]
        case .splitHorizontal: return ["split view", "top", "bottom"]
        case .unsplit: return ["close split", "remove split"]
        case .newEmptySplit: return ["new split", "split view", "add split"]
        case .addSplitTop: return ["split view", "top", "above"]
        case .addSplitLeft: return ["split view", "left", "before"]
        case .addSplitRight: return ["split view", "right", "after"]
        case .addSplitBottom: return ["split view", "bottom", "below"]
        case .newWindow: return ["open window"]
        case .newPrivateWindow: return ["incognito", "private browsing"]
        case .newFolder: return ["folder", "sidebar"]
        case .pinTab: return ["pin", "favorite", "sidebar"]
        case .unpinTab: return ["unpin", "regular tab", "sidebar"]
        case .addToFavorite: return ["favorite", "pin", "sidebar"]
        case .removeFromFavorite: return ["unfavorite", "unpin", "sidebar"]
        case .newBoost: return ["boost", "customize website", "site style"]
        case .closeBrowser: return ["quit", "exit"]
        case .toggleFullScreen: return ["fullscreen"]
        case .openDevTools: return ["inspect", "developer", "console"]
        case .viewDownloads: return ["download"]
        case .viewHistory: return ["history", "visited"]
        case .openSettings: return ["preferences", "options"]
        case .manageExtensions: return ["addons", "plugins"]
        case .printPage: return ["printer", "page"]
        case .captureScreenshot: return ["screenshot", "capture", "snapshot", "camera"]
        case .findInPage: return ["find", "search page"]
        case .actualSize: return ["reset zoom", "100%"]
        case .toggleSidebar: return ["show sidebar", "hide sidebar"]
        case .copyCurrentURL: return ["copy link", "copy address"]
        case .hardReload: return ["reload without cache", "force reload"]
        case .toggleReaderMode: return ["reader", "reading mode"]
        case .muteUnmuteAudio: return ["mute tab", "unmute tab", "sound"]
        case .customizeSpaceGradient: return ["theme", "color", "appearance"]
        case .toggleTabsOnRight: return ["sidebar right", "move sidebar", "tabs right"]
        case .switchToAutomaticAppearance: return ["system appearance", "auto theme"]
        case .switchToLightMode: return ["light appearance", "light theme"]
        case .switchToDarkMode: return ["dark appearance", "dark theme"]
        default:
            return [category.displayName]
        }
    }

    public var isPresentedInCommandPalette: Bool {
        switch self {
        case .newTab,
             .undoCloseTab,
             .splitGrid,
             .splitVertical,
             .splitHorizontal,
             .focusAddressBar,
             .toggleReaderMode,
             .muteUnmuteAudio,
             .goToTab1, .goToTab2, .goToTab3, .goToTab4,
             .goToTab5, .goToTab6, .goToTab7, .goToTab8, .goToLastTab,
             .goToSpace1, .goToSpace2, .goToSpace3, .goToSpace4,
             .goToSpace5, .goToSpace6, .goToSpace7, .goToSpace8,
             .goToSpace9, .goToSpace10:
            return false
        default:
            return true
        }
    }
}
