import AppKit
import SumiDomain

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
             .copyCurrentURL, .hardReload, .muteUnmuteAudio:
            .page
        case .newTab, .closeTab, .nextTab, .previousTab, .goToTab1,
             .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6,
             .goToTab7, .goToTab8, .goToLastTab, .duplicateTab,
             .splitGrid, .splitVertical, .splitHorizontal, .unsplit,
             .newEmptySplit:
            .tabs
        case .newWindow, .closeBrowser:
            .application
        case .undoCloseTab, .nextSpace, .previousSpace, .closeWindow,
             .toggleFullScreen, .expandAllFolders:
            .windowsAndSpaces
        case .viewDownloads, .toggleSidebar, .toggleReaderMode,
             .customizeSpaceGradient:
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
        precondition(
            handled,
            "Contextual shortcut domain rejected its action: \(action)"
        )
        return true
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

    func dismissFloatingBar(
        in windowState: BrowserWindowState,
        preserveDraft: Bool
    ) {
        overlays.dismissFloatingBar(
            in: windowState,
            preserveDraft: preserveDraft
        )
    }
}
