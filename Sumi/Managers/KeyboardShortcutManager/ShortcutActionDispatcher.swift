import AppKit
import Foundation

@MainActor
protocol ShortcutActionRouting: AnyObject {
    func showFindBar()
    func goBackInActiveWindow()
    func goForwardInActiveWindow()
    func refreshCurrentTabInActiveWindow()
    func clearCurrentPageCookies()
    func openNewTabSurfaceInActiveWindow()
    func closeCurrentTab()
    func undoCloseTab()
    func selectNextTabInActiveWindow()
    func selectPreviousTabInActiveWindow()
    func selectTabByIndexInActiveWindow(_ index: Int)
    func selectLastTabInActiveWindow()
    func duplicateCurrentTab()
    func setActiveSplitLayout(_ layoutKind: SplitLayoutKind)
    func unsplitActiveWindow()
    func createEmptySplitInActiveWindow()
    func selectNextSpaceInActiveWindow()
    func selectPreviousSpaceInActiveWindow()
    func createNewWindow()
    func closeActiveWindow()
    func showQuitDialog()
    func toggleFullScreenForActiveWindow()
    func openWebInspector()
    func showDownloads()
    func showHistory()
    func expandAllFoldersInSidebar()
    func activePageURLForActiveWindow() -> URL?
    func focusFloatingBarForActiveWindow(prefill: String, navigateCurrentTab: Bool)
    func zoomInCurrentTab()
    func zoomOutCurrentTab()
    func resetZoomCurrentTab()
    func toggleSidebar()
    func copyCurrentURL()
    func hardReloadCurrentPage()
    func toggleReaderModeInActiveWindow()
    func toggleMuteCurrentTabInActiveWindow()
    func showGradientEditor()
}

@MainActor
protocol KeyboardShortcutChromeRouting: AnyObject {
    var isFindBarVisibleForShortcutRouting: Bool { get }
    func hideFindBarForShortcutRouting()
    func isNativeModalPresentedForShortcutRouting(in window: NSWindow) -> Bool
    func dismissFloatingBarForShortcutRouting(in windowState: BrowserWindowState, preserveDraft: Bool)
}

@MainActor
final class ShortcutActionDispatcher {
    weak var actionRouter: (any ShortcutActionRouting)?

    func execute(_ action: ShortcutAction) {
        guard let actionRouter else { return }

        if case .findInPage = action {
            actionRouter.showFindBar()
            postShortcutExecuted(action)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let actionRouter = self.actionRouter else { return }

            switch action {
            case .goBack:
                actionRouter.goBackInActiveWindow()
            case .goForward:
                actionRouter.goForwardInActiveWindow()
            case .refresh:
                actionRouter.refreshCurrentTabInActiveWindow()
            case .clearCookiesAndRefresh:
                actionRouter.clearCurrentPageCookies()
                actionRouter.refreshCurrentTabInActiveWindow()
            case .newTab:
                actionRouter.openNewTabSurfaceInActiveWindow()
            case .closeTab:
                actionRouter.closeCurrentTab()
            case .undoCloseTab:
                actionRouter.undoCloseTab()
            case .nextTab:
                actionRouter.selectNextTabInActiveWindow()
            case .previousTab:
                actionRouter.selectPreviousTabInActiveWindow()
            case .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8:
                let tabIndex = Int(action.rawValue.components(separatedBy: "_").last ?? "0") ?? 1
                actionRouter.selectTabByIndexInActiveWindow(tabIndex - 1)
            case .goToLastTab:
                actionRouter.selectLastTabInActiveWindow()
            case .duplicateTab:
                actionRouter.duplicateCurrentTab()
            case .splitGrid:
                actionRouter.setActiveSplitLayout(.grid)
            case .splitVertical:
                actionRouter.setActiveSplitLayout(.vertical)
            case .splitHorizontal:
                actionRouter.setActiveSplitLayout(.horizontal)
            case .unsplit:
                actionRouter.unsplitActiveWindow()
            case .newEmptySplit:
                actionRouter.createEmptySplitInActiveWindow()
            case .nextSpace:
                actionRouter.selectNextSpaceInActiveWindow()
            case .previousSpace:
                actionRouter.selectPreviousSpaceInActiveWindow()
            case .newWindow:
                actionRouter.createNewWindow()
            case .closeWindow:
                actionRouter.closeActiveWindow()
            case .closeBrowser:
                actionRouter.showQuitDialog()
            case .toggleFullScreen:
                actionRouter.toggleFullScreenForActiveWindow()
            case .openDevTools:
                actionRouter.openWebInspector()
            case .viewDownloads:
                actionRouter.showDownloads()
            case .viewHistory:
                actionRouter.showHistory()
            case .expandAllFolders:
                actionRouter.expandAllFoldersInSidebar()
            case .focusAddressBar:
                let currentURL = actionRouter.activePageURLForActiveWindow()?.absoluteString ?? ""
                actionRouter.focusFloatingBarForActiveWindow(
                    prefill: currentURL,
                    navigateCurrentTab: true
                )
            case .findInPage:
                break
            case .zoomIn:
                actionRouter.zoomInCurrentTab()
            case .zoomOut:
                actionRouter.zoomOutCurrentTab()
            case .actualSize:
                actionRouter.resetZoomCurrentTab()
            case .toggleSidebar:
                actionRouter.toggleSidebar()
            case .copyCurrentURL:
                actionRouter.copyCurrentURL()
            case .hardReload:
                actionRouter.hardReloadCurrentPage()
            case .toggleReaderMode:
                actionRouter.toggleReaderModeInActiveWindow()
            case .muteUnmuteAudio:
                actionRouter.toggleMuteCurrentTabInActiveWindow()
            case .customizeSpaceGradient:
                actionRouter.showGradientEditor()
            }

            self.postShortcutExecuted(action)
        }
    }

    private func postShortcutExecuted(_ action: ShortcutAction) {
        NotificationCenter.default.post(
            name: .shortcutExecuted,
            object: nil,
            userInfo: ["action": action]
        )
    }
}

extension BrowserManager: ShortcutActionRouting, KeyboardShortcutChromeRouting {
    func focusFloatingBarForActiveWindow(prefill: String, navigateCurrentTab: Bool) {
        focusFloatingBarForActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: .keyboard
        )
    }

    var isFindBarVisibleForShortcutRouting: Bool {
        findManager.isFindBarVisible
    }

    func hideFindBarForShortcutRouting() {
        findManager.hideFindBar()
    }

    func isNativeModalPresentedForShortcutRouting(in window: NSWindow) -> Bool {
        isNativeModalPresented(in: window)
    }

    func dismissFloatingBarForShortcutRouting(in windowState: BrowserWindowState, preserveDraft: Bool) {
        dismissFloatingBar(in: windowState, preserveDraft: preserveDraft)
    }
}
