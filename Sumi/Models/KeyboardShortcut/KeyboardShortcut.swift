//
//  KeyboardShortcut.swift
//  Sumi
//
//  Created by Jonathan Caudill on 09/30/2025.
//

import Foundation
import AppKit

// MARK: - Keyboard Shortcut Data Model
struct KeyboardShortcut: Identifiable, Hashable, Codable {
    let id: UUID
    let action: ShortcutAction
    var keyCombination: KeyCombination
    var isEnabled: Bool = true
    var isCustomizable: Bool = true

    init(
        id: UUID = UUID(),
        action: ShortcutAction,
        keyCombination: KeyCombination,
        isEnabled: Bool = true,
        isCustomizable: Bool = true
    ) {
        self.id = id
        self.action = action
        self.keyCombination = keyCombination
        self.isEnabled = isEnabled
        self.isCustomizable = isCustomizable
    }

    /// Unique hash for O(1) lookup: "cmd+shift+t"
    var lookupKey: String {
        keyCombination.lookupKey
    }
}

// MARK: - Shortcut Actions
enum ShortcutAction: String, CaseIterable, Hashable, Codable {
    // Navigation
    case goBack = "go_back"
    case goForward = "go_forward"
    case refresh = "refresh"
    case clearCookiesAndRefresh = "clear_cookies_and_refresh"

    // Tab Management
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

    // Space Management
    case nextSpace = "next_space"
    case previousSpace = "previous_space"

    // Window Management
    case newWindow = "new_window"
    case closeWindow = "close_window"
    case closeBrowser = "close_browser"
    case toggleFullScreen = "toggle_full_screen"

    // Tools & Features
    case openCommandPalette = "open_command_palette"
    case openDevTools = "open_dev_tools"
    case viewDownloads = "view_downloads"
    case viewHistory = "view_history"
    case expandAllFolders = "expand_all_folders"

    // Missing actions that exist in SumiCommands but not here
    case focusAddressBar = "focus_address_bar"  // Cmd+L
    case findInPage = "find_in_page"            // Cmd+F
    case zoomIn = "zoom_in"                     // Cmd++
    case zoomOut = "zoom_out"                   // Cmd+-
    case actualSize = "actual_size"             // Cmd+0

    // NEW: Menu items in SumiCommands that were missing ShortcutAction definitions
    case toggleSidebar = "toggle_sidebar"                      // Cmd+S
    case copyCurrentURL = "copy_current_url"                   // Cmd+Shift+C
    case hardReload = "hard_reload"                            // Cmd+Shift+R
    case muteUnmuteAudio = "mute_unmute_audio"                 // Cmd+M
    case customizeSpaceGradient = "customize_space_gradient"   // Cmd+Shift+G

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
        case .goBack, .goForward, .refresh, .clearCookiesAndRefresh:
            return .navigation
        case .newTab, .closeTab, .undoCloseTab, .nextTab, .previousTab, .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8, .goToLastTab, .duplicateTab, .toggleTopBarAddressView:
            return .tabs
        case .nextSpace, .previousSpace:
            return .spaces
        case .newWindow, .closeWindow, .closeBrowser, .toggleFullScreen:
            return .window
        case .openCommandPalette, .openDevTools, .viewDownloads, .viewHistory, .expandAllFolders:
            return .tools
        case .focusAddressBar, .findInPage:
            return .navigation
        case .zoomIn, .zoomOut, .actualSize:
            return .tools
        case .toggleSidebar:
            return .window
        case .copyCurrentURL:
            return .tools
        case .hardReload:
            return .navigation
        case .muteUnmuteAudio:
            return .tools
        case .customizeSpaceGradient:
            return .spaces
        }
    }
}

// MARK: - Shortcut Categories
enum ShortcutCategory: String, CaseIterable, Hashable, Codable {
    case navigation = "navigation"
    case tabs = "tabs"
    case spaces = "spaces"
    case window = "window"
    case tools = "tools"

    var displayName: String {
        switch self {
        case .navigation: return "Navigation"
        case .tabs: return "Tabs"
        case .spaces: return "Spaces"
        case .window: return "Window"
        case .tools: return "Tools"
        }
    }

    var icon: String {
        switch self {
        case .navigation: return "arrow.left.arrow.right"
        case .tabs: return "doc.on.doc"
        case .spaces: return "rectangle.3.group"
        case .window: return "macwindow"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Key Combination
struct KeyCombination: Hashable, Codable {
    let key: String
    let modifiers: Modifiers

    init(key: String, modifiers: Modifiers = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    var displayString: String {
        guard !key.isEmpty else { return "Not Set" }
        var parts = modifiers.displayStrings
        parts.append(key.uppercased())
        return parts.joined(separator: " + ")
    }

    var isEmpty: Bool {
        key.isEmpty
    }

    private static let physicalKeyMap: [UInt16: String] = [
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g", 0x06: "z", 0x07: "x",
        0x08: "c", 0x09: "v", 0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y",
        0x11: "t", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "o", 0x20: "u",
        0x21: "[", 0x22: "i", 0x23: "p", 0x24: "return", 0x25: "l", 0x26: "j", 0x27: "'",
        0x28: "k", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "n", 0x2E: "m", 0x2F: ".",
        0x30: "tab", 0x31: "space", 0x33: "delete", 0x35: "escape", 0x7B: "leftarrow",
        0x7C: "rightarrow", 0x7D: "downarrow", 0x7E: "uparrow"
    ]

    private static func canonicalPhysicalKey(for event: NSEvent) -> String? {
        physicalKeyMap[event.keyCode]
    }

    private static let namedPhysicalKeys: Set<String> = [
        "return", "tab", "space", "delete", "escape", "leftarrow", "rightarrow", "downarrow", "uparrow"
    ]

    /// Unique hash for O(1) lookup: "cmd+shift+t"
    var lookupKey: String {
        guard !key.isEmpty else { return "" }
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.shift) { parts.append("shift") }
        parts.append(key.lowercased())
        return parts.joined(separator: "+")
    }

    /// Initialize from NSEvent
    init?(from event: NSEvent) {
        let keyWithoutModifiers = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let keyWithModifiers = event.characters?.lowercased() ?? ""
        let physicalKey = Self.canonicalPhysicalKey(for: event)

        let resolvedKey: String
        if keyWithoutModifiers == "=", keyWithModifiers == "+" {
            resolvedKey = "+"
        } else if let physicalKey, Self.namedPhysicalKeys.contains(physicalKey) {
            resolvedKey = physicalKey
        } else if !keyWithoutModifiers.isEmpty, keyWithoutModifiers.canBeConverted(to: .ascii) {
            resolvedKey = keyWithoutModifiers
        } else if let physicalKey {
            resolvedKey = physicalKey
        } else if !keyWithModifiers.isEmpty {
            resolvedKey = keyWithModifiers
        } else {
            return nil
        }

        var modifiers: Modifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }

        self.key = resolvedKey
        self.modifiers = modifiers
    }
}

// MARK: - Modifiers
struct Modifiers: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let command = Modifiers(rawValue: 1 << 0)
    static let option = Modifiers(rawValue: 1 << 1)
    static let control = Modifiers(rawValue: 1 << 2)
    static let shift = Modifiers(rawValue: 1 << 3)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(eventModifierFlags: NSEvent.ModifierFlags) {
        var modifiers: Modifiers = []
        if eventModifierFlags.contains(.command) { modifiers.insert(.command) }
        if eventModifierFlags.contains(.option) { modifiers.insert(.option) }
        if eventModifierFlags.contains(.control) { modifiers.insert(.control) }
        if eventModifierFlags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }

    var displayStrings: [String] {
        var strings: [String] = []
        if contains(.command) { strings.append("⌘") }
        if contains(.option) { strings.append("⌥") }
        if contains(.control) { strings.append("⌃") }
        if contains(.shift) { strings.append("⇧") }
        return strings
    }
}

// MARK: - Default Shortcuts
extension KeyboardShortcut {
    static var defaultShortcuts: [KeyboardShortcut] {
        [
            // Navigation
            KeyboardShortcut(action: .goBack, keyCombination: KeyCombination(key: "[", modifiers: [.command])),
            KeyboardShortcut(action: .goForward, keyCombination: KeyCombination(key: "]", modifiers: [.command])),
            KeyboardShortcut(action: .refresh, keyCombination: KeyCombination(key: "r", modifiers: [.command])),
            KeyboardShortcut(action: .clearCookiesAndRefresh, keyCombination: KeyCombination(key: "r", modifiers: [.command, .shift, .option])),

            // Tab Management
            KeyboardShortcut(action: .newTab, keyCombination: KeyCombination(key: "t", modifiers: [.command])),
            KeyboardShortcut(action: .closeTab, keyCombination: KeyCombination(key: "w", modifiers: [.command])),
            KeyboardShortcut(action: .undoCloseTab, keyCombination: KeyCombination(key: "t", modifiers: [.command, .shift])),
            KeyboardShortcut(action: .nextTab, keyCombination: KeyCombination(key: "tab", modifiers: [.control])),
            KeyboardShortcut(action: .previousTab, keyCombination: KeyCombination(key: "tab", modifiers: [.control, .shift])),
            KeyboardShortcut(action: .goToTab1, keyCombination: KeyCombination(key: "1", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab2, keyCombination: KeyCombination(key: "2", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab3, keyCombination: KeyCombination(key: "3", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab4, keyCombination: KeyCombination(key: "4", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab5, keyCombination: KeyCombination(key: "5", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab6, keyCombination: KeyCombination(key: "6", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab7, keyCombination: KeyCombination(key: "7", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab8, keyCombination: KeyCombination(key: "8", modifiers: [.command])),
            KeyboardShortcut(action: .goToLastTab, keyCombination: KeyCombination(key: "9", modifiers: [.command])),
            KeyboardShortcut(action: .duplicateTab, keyCombination: KeyCombination(key: "d", modifiers: [.option])),

            // Space Management
            KeyboardShortcut(action: .nextSpace, keyCombination: KeyCombination(key: "]", modifiers: [.command, .control])),
            KeyboardShortcut(action: .previousSpace, keyCombination: KeyCombination(key: "[", modifiers: [.command, .control])),

            // Window Management
            KeyboardShortcut(action: .newWindow, keyCombination: KeyCombination(key: "n", modifiers: [.command])),
            KeyboardShortcut(action: .closeWindow, keyCombination: KeyCombination(key: "w", modifiers: [.command, .shift])),
            KeyboardShortcut(action: .closeBrowser, keyCombination: KeyCombination(key: "q", modifiers: [.command])),
            KeyboardShortcut(action: .toggleFullScreen, keyCombination: KeyCombination(key: "f", modifiers: [.command, .control])),

            // Tools & Features
            KeyboardShortcut(action: .openCommandPalette, keyCombination: KeyCombination(key: "p", modifiers: [.command, .shift])),
            KeyboardShortcut(action: .openDevTools, keyCombination: KeyCombination(key: "i", modifiers: [.command, .option])),
            KeyboardShortcut(action: .viewDownloads, keyCombination: KeyCombination(key: "j", modifiers: [.command, .shift])),
            KeyboardShortcut(action: .viewHistory, keyCombination: KeyCombination(key: "y", modifiers: [.command])),
            KeyboardShortcut(action: .expandAllFolders, keyCombination: KeyCombination(key: "e", modifiers: [.command, .shift])),

            // Missing shortcuts that exist in SumiCommands
            KeyboardShortcut(action: .focusAddressBar, keyCombination: KeyCombination(key: "l", modifiers: [.command])),
            KeyboardShortcut(action: .findInPage, keyCombination: KeyCombination(key: "f", modifiers: [.command])),
            KeyboardShortcut(action: .zoomIn, keyCombination: KeyCombination(key: "+", modifiers: [.command])),
            KeyboardShortcut(action: .zoomOut, keyCombination: KeyCombination(key: "-", modifiers: [.command])),
            KeyboardShortcut(action: .actualSize, keyCombination: KeyCombination(key: "0", modifiers: [.command])),

            // NEW: Menu shortcuts that were missing from ShortcutAction
            KeyboardShortcut(action: .toggleSidebar, keyCombination: KeyCombination(key: "s", modifiers: [.command])),
            KeyboardShortcut(action: .copyCurrentURL, keyCombination: KeyCombination(key: "c", modifiers: [.command, .shift])),
            KeyboardShortcut(action: .hardReload, keyCombination: KeyCombination(key: "r", modifiers: [.command, .shift])),
            KeyboardShortcut(action: .muteUnmuteAudio, keyCombination: KeyCombination(key: ""), isEnabled: false),
            KeyboardShortcut(action: .customizeSpaceGradient, keyCombination: KeyCombination(key: "g", modifiers: [.command, .shift]))
        ]
    }
}
