import Foundation

enum DefaultKeyboardShortcuts {
    static let shortcuts: [KeyboardShortcut] = [
        KeyboardShortcut(action: .goBack, keyCombination: KeyCombination(key: "[", modifiers: [.command])),
        KeyboardShortcut(action: .goForward, keyCombination: KeyCombination(key: "]", modifiers: [.command])),
        KeyboardShortcut(action: .refresh, keyCombination: KeyCombination(key: "r", modifiers: [.command])),
        KeyboardShortcut(action: .clearCookiesAndRefresh, keyCombination: KeyCombination(key: "r", modifiers: [.command, .shift, .option])),
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
        KeyboardShortcut(action: .nextSpace, keyCombination: KeyCombination(key: "]", modifiers: [.command, .control])),
        KeyboardShortcut(action: .previousSpace, keyCombination: KeyCombination(key: "[", modifiers: [.command, .control])),
        KeyboardShortcut(action: .newWindow, keyCombination: KeyCombination(key: "n", modifiers: [.command])),
        KeyboardShortcut(action: .closeWindow, keyCombination: KeyCombination(key: "w", modifiers: [.command, .shift])),
        KeyboardShortcut(action: .closeBrowser, keyCombination: KeyCombination(key: "q", modifiers: [.command])),
        KeyboardShortcut(action: .toggleFullScreen, keyCombination: KeyCombination(key: "f", modifiers: [.command, .control])),
        KeyboardShortcut(action: .openDevTools, keyCombination: KeyCombination(key: "i", modifiers: [.command, .option])),
        KeyboardShortcut(action: .viewDownloads, keyCombination: KeyCombination(key: "j", modifiers: [.command, .shift])),
        KeyboardShortcut(action: .viewHistory, keyCombination: KeyCombination(key: "y", modifiers: [.command])),
        KeyboardShortcut(action: .expandAllFolders, keyCombination: KeyCombination(key: "e", modifiers: [.command, .shift])),
        KeyboardShortcut(action: .focusAddressBar, keyCombination: KeyCombination(key: "l", modifiers: [.command])),
        KeyboardShortcut(action: .findInPage, keyCombination: KeyCombination(key: "f", modifiers: [.command])),
        KeyboardShortcut(action: .zoomIn, keyCombination: KeyCombination(key: "+", modifiers: [.command])),
        KeyboardShortcut(action: .zoomOut, keyCombination: KeyCombination(key: "-", modifiers: [.command])),
        KeyboardShortcut(action: .actualSize, keyCombination: KeyCombination(key: "0", modifiers: [.command])),
        KeyboardShortcut(action: .toggleSidebar, keyCombination: KeyCombination(key: "s", modifiers: [.command])),
        KeyboardShortcut(action: .copyCurrentURL, keyCombination: KeyCombination(key: "c", modifiers: [.command, .shift])),
        KeyboardShortcut(action: .hardReload, keyCombination: KeyCombination(key: "r", modifiers: [.command, .shift])),
        KeyboardShortcut(action: .muteUnmuteAudio, keyCombination: nil),
        KeyboardShortcut(action: .customizeSpaceGradient, keyCombination: KeyCombination(key: "g", modifiers: [.command, .shift]))
    ]

    static var shortcutsByAction: [ShortcutAction: KeyboardShortcut] {
        Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.action, $0) })
    }
}
