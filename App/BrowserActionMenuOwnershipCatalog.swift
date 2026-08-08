import SumiDomain

/// Identity-level contract for the one menu location that owns each
/// configurable Browser Action. Menu presentation remains with its native
/// command group because titles and availability can be window-dependent.
enum BrowserActionMenuOwnershipCatalog {
    static let file: [ShortcutAction] = [
        .newTab, .newWindow, .newPrivateWindow, .focusAddressBar,
        .copyCurrentURL, .printPage,
    ]

    static let history: [ShortcutAction] = [
        .goBack, .goForward, .undoCloseTab, .viewHistory,
    ]

    static let tabs: [ShortcutAction] = [
        .closeTab, .nextTab, .previousTab,
        .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5,
        .goToTab6, .goToTab7, .goToTab8, .goToLastTab,
        .duplicateTab, .pinTab, .unpinTab,
        .addToEssentials, .removeFromEssentials,
    ]

    static let splitView: [ShortcutAction] = [
        .splitGrid, .splitVertical, .splitHorizontal, .newEmptySplit,
        .addSplitTop, .addSplitLeft, .addSplitRight, .addSplitBottom,
        .unsplit,
    ]

    static let spaces: [ShortcutAction] = [
        .newFolder, .nextSpace, .previousSpace,
        .goToSpace1, .goToSpace2, .goToSpace3, .goToSpace4, .goToSpace5,
        .goToSpace6, .goToSpace7, .goToSpace8, .goToSpace9, .goToSpace10,
        .expandAllFolders,
    ]

    static let pageAndView: [ShortcutAction] = [
        .refresh, .clearCookiesAndRefresh, .findInPage,
        .zoomIn, .zoomOut, .actualSize, .hardReload, .openDevTools,
        .toggleReaderMode, .muteUnmuteAudio, .newBoost,
    ]

    static let browserChrome: [ShortcutAction] = [
        .toggleSidebar, .viewDownloads, .manageExtensions,
        .captureScreenshot, .toggleTabsOnRight,
    ]

    static let appearance: [ShortcutAction] = [
        .customizeSpaceGradient, .switchToAutomaticAppearance,
        .switchToLightMode, .switchToDarkMode,
    ]

    static let window: [ShortcutAction] = [.closeWindow]

    static let allActions: [ShortcutAction] =
        file + history + tabs + splitView + spaces + pageAndView
        + browserChrome + appearance + window
}
