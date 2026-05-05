import Foundation

enum ShortcutAction: String, CaseIterable, Hashable, Codable {
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
    case toggleTopBarAddressView = "toggle_top_bar_address_view"

    case nextSpace = "next_space"
    case previousSpace = "previous_space"

    case newWindow = "new_window"
    case closeWindow = "close_window"
    case closeBrowser = "close_browser"
    case toggleFullScreen = "toggle_full_screen"

    case openCommandPalette = "open_command_palette"
    case openDevTools = "open_dev_tools"
    case viewDownloads = "view_downloads"
    case viewHistory = "view_history"
    case expandAllFolders = "expand_all_folders"
    case focusAddressBar = "focus_address_bar"
    case findInPage = "find_in_page"
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case actualSize = "actual_size"
    case toggleSidebar = "toggle_sidebar"
    case copyCurrentURL = "copy_current_url"
    case hardReload = "hard_reload"
    case muteUnmuteAudio = "mute_unmute_audio"
    case customizeSpaceGradient = "customize_space_gradient"

    var displayName: String {
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
        case .toggleTopBarAddressView: return "Focus Sidebar URL Bar"
        case .nextSpace: return "Next Space"
        case .previousSpace: return "Previous Space"
        case .newWindow: return "New Window"
        case .closeWindow: return "Close Window"
        case .closeBrowser: return "Close Browser"
        case .toggleFullScreen: return "Toggle Full Screen"
        case .openCommandPalette: return "Open Command Palette"
        case .openDevTools: return "Developer Tools"
        case .viewDownloads: return "View Downloads"
        case .viewHistory: return "View History"
        case .expandAllFolders: return "Expand All Folders"
        case .focusAddressBar: return "Focus Address Bar"
        case .findInPage: return "Find in Page"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .actualSize: return "Actual Size"
        case .toggleSidebar: return "Toggle Sidebar"
        case .copyCurrentURL: return "Copy Current URL"
        case .hardReload: return "Hard Reload"
        case .muteUnmuteAudio: return "Mute/Unmute Audio"
        case .customizeSpaceGradient: return "Customize Space Gradient"
        }
    }

    var category: ShortcutCategory {
        switch self {
        case .goBack, .goForward, .refresh, .clearCookiesAndRefresh, .focusAddressBar, .findInPage, .hardReload:
            return .navigation
        case .newTab, .closeTab, .undoCloseTab, .nextTab, .previousTab, .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8, .goToLastTab, .duplicateTab, .toggleTopBarAddressView:
            return .tabs
        case .nextSpace, .previousSpace, .customizeSpaceGradient:
            return .spaces
        case .newWindow, .closeWindow, .closeBrowser, .toggleFullScreen, .toggleSidebar:
            return .window
        case .openCommandPalette, .openDevTools, .viewDownloads, .viewHistory, .expandAllFolders, .zoomIn, .zoomOut, .actualSize, .copyCurrentURL, .muteUnmuteAudio:
            return .tools
        }
    }
}
