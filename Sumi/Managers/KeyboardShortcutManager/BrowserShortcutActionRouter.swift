import AppKit
import SumiDomain

enum CommandPaletteShortcutExecutionOutcome {
    case dismissPalette
    case paletteReplaced
}

private enum BrowserShortcutCommandDomain {
    case application
    case page
    case tabs
    case windowsAndSpaces
    case chrome
    case overlays
}

private extension ShortcutAction {
    var browserCommandDomain: BrowserShortcutCommandDomain {
        switch self {
        case .goBack, .goForward, .refresh, .clearCookiesAndRefresh,
             .openDevTools, .viewHistory, .zoomIn, .zoomOut, .actualSize,
             .copyCurrentURL, .hardReload, .muteUnmuteAudio, .printPage,
             .captureScreenshot, .newBoost:
            .page
        case .newTab, .closeTab, .nextTab, .previousTab, .goToTab1,
             .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6,
             .goToTab7, .goToTab8, .goToLastTab, .duplicateTab,
             .splitGrid, .splitVertical, .splitHorizontal, .unsplit,
             .newEmptySplit, .addSplitTop, .addSplitLeft, .addSplitRight,
             .addSplitBottom, .pinTab, .unpinTab, .addToFavorite,
             .removeFromFavorite:
            .tabs
        case .newWindow, .newPrivateWindow, .closeBrowser:
            .application
        case .undoCloseTab, .nextSpace, .previousSpace, .closeWindow,
             .toggleFullScreen, .expandAllFolders,
             .goToSpace1, .goToSpace2, .goToSpace3, .goToSpace4, .goToSpace5,
             .goToSpace6, .goToSpace7, .goToSpace8, .goToSpace9, .goToSpace10:
            .windowsAndSpaces
        case .viewDownloads, .toggleSidebar, .toggleReaderMode,
             .customizeSpaceGradient, .newFolder, .openSettings,
             .manageExtensions, .toggleTabsOnRight,
             .switchToAutomaticAppearance, .switchToLightMode,
             .switchToDarkMode:
            .chrome
        case .findInPage, .focusAddressBar:
            .overlays
        }
    }
}

/// Routes one shortcut action to the behaviorful domain transaction that owns it.
@MainActor
final class BrowserShortcutActionRouter {
    private let page: BrowserShortcutPageCommandDispatcher
    private let tabs: BrowserShortcutTabCommandDispatcher
    private let windowsAndSpaces: BrowserShortcutWindowSpaceCommandDispatcher
    private let chrome: BrowserShortcutChromeCommandDispatcher
    private let overlays: BrowserShortcutOverlayCommandDispatcher

    init(
        page: BrowserShortcutPageCommandDispatcher,
        tabs: BrowserShortcutTabCommandDispatcher,
        windowsAndSpaces: BrowserShortcutWindowSpaceCommandDispatcher,
        chrome: BrowserShortcutChromeCommandDispatcher,
        overlays: BrowserShortcutOverlayCommandDispatcher
    ) {
        self.page = page
        self.tabs = tabs
        self.windowsAndSpaces = windowsAndSpaces
        self.chrome = chrome
        self.overlays = overlays
    }

    @discardableResult
    func execute(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        let handled = switch action.browserCommandDomain {
        case .application:
            false
        case .tabs:
            tabs.dispatch(action, in: context)
        case .windowsAndSpaces:
            windowsAndSpaces.dispatch(action, in: context)
        case .page:
            page.dispatch(action, in: context)
        case .chrome:
            chrome.dispatch(action, in: context)
        case .overlays:
            overlays.dispatch(action, in: context)
        }
        return handled
    }

    func canExecute(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        return switch action.browserCommandDomain {
        case .application:
            false
        case .tabs:
            tabs.canDispatch(action, in: context)
        case .windowsAndSpaces:
            windowsAndSpaces.canDispatch(action, in: context)
        case .page:
            page.canDispatch(action, in: context)
        case .chrome:
            chrome.canDispatch(action, in: context)
        case .overlays:
            overlays.canDispatch(action, in: context)
        }
    }

    func executeFromCommandPalette(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> CommandPaletteShortcutExecutionOutcome? {
        if case .tabs = action.browserCommandDomain {
            return tabs.dispatchFromCommandPalette(action, in: context)
        }
        guard execute(action, in: context) else { return nil }
        return .dismissPalette
    }

    func canExecuteApplicationAction(_ action: ShortcutAction) -> Bool {
        action == .newWindow
            || action == .newPrivateWindow
            || action == .closeBrowser
    }

    @discardableResult
    func executeApplicationAction(_ action: ShortcutAction) -> Bool {
        windowsAndSpaces.dispatchApplicationAction(action)
    }

    var isFindBarVisible: Bool { overlays.isFindBarVisible }

    func hideFindBar() {
        overlays.hideFindBar()
    }

    func isNativeModalPresented(in window: NSWindow) -> Bool {
        overlays.isNativeModalPresented(in: window)
    }

    func dismissCommandPalette(
        in windowState: BrowserWindowState,
        preserveDraft: Bool
    ) {
        overlays.dismissCommandPalette(
            in: windowState,
            preserveDraft: preserveDraft
        )
    }
}
