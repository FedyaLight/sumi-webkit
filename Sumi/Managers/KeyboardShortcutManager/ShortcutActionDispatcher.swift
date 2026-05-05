import AppKit
import Foundation

@MainActor
final class ShortcutActionDispatcher {
    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?

    func execute(_ action: ShortcutAction) {
        guard let browserManager else { return }

        if case .findInPage = action {
            browserManager.showFindBar()
            postShortcutExecuted(action)
            return
        }

        DispatchQueue.main.async { [weak self, weak browserManager] in
            guard let self, let browserManager else { return }

            switch action {
            case .goBack:
                if let tab = browserManager.currentTabForActiveWindow(),
                   let windowId = self.windowRegistry?.activeWindow?.id,
                   let webView = browserManager.getWebView(for: tab.id, in: windowId),
                   webView.canGoBack {
                    webView.goBack()
                }
            case .goForward:
                if let tab = browserManager.currentTabForActiveWindow(),
                   let windowId = self.windowRegistry?.activeWindow?.id,
                   let webView = browserManager.getWebView(for: tab.id, in: windowId),
                   webView.canGoForward {
                    webView.goForward()
                }
            case .refresh:
                browserManager.refreshCurrentTabInActiveWindow()
            case .clearCookiesAndRefresh:
                browserManager.clearCurrentPageCookies()
                browserManager.refreshCurrentTabInActiveWindow()
            case .newTab:
                browserManager.openNewTabSurfaceInActiveWindow()
            case .closeTab:
                browserManager.closeCurrentTab()
            case .undoCloseTab:
                browserManager.undoCloseTab()
            case .nextTab:
                browserManager.selectNextTabInActiveWindow()
            case .previousTab:
                browserManager.selectPreviousTabInActiveWindow()
            case .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8:
                let tabIndex = Int(action.rawValue.components(separatedBy: "_").last ?? "0") ?? 1
                browserManager.selectTabByIndexInActiveWindow(tabIndex - 1)
            case .goToLastTab:
                browserManager.selectLastTabInActiveWindow()
            case .duplicateTab:
                browserManager.duplicateCurrentTab()
            case .toggleTopBarAddressView:
                browserManager.toggleTopBarAddressView()
            case .nextSpace:
                browserManager.selectNextSpaceInActiveWindow()
            case .previousSpace:
                browserManager.selectPreviousSpaceInActiveWindow()
            case .newWindow:
                browserManager.createNewWindow()
            case .closeWindow:
                browserManager.closeActiveWindow()
            case .closeBrowser:
                browserManager.showQuitDialog()
            case .toggleFullScreen:
                browserManager.toggleFullScreenForActiveWindow()
            case .openDevTools:
                browserManager.openWebInspector()
            case .viewDownloads:
                browserManager.showDownloads()
            case .viewHistory:
                browserManager.showHistory()
            case .expandAllFolders:
                browserManager.expandAllFoldersInSidebar()
            case .focusAddressBar:
                let currentURL = browserManager.currentTabForActiveWindow()?.url.absoluteString ?? ""
                browserManager.openCommandPaletteForActiveWindow(
                    reason: .keyboard,
                    prefill: currentURL,
                    navigateCurrentTab: true
                )
            case .findInPage:
                break
            case .zoomIn:
                browserManager.zoomInCurrentTab()
            case .zoomOut:
                browserManager.zoomOutCurrentTab()
            case .actualSize:
                browserManager.resetZoomCurrentTab()
            case .toggleSidebar:
                browserManager.toggleSidebar()
            case .copyCurrentURL:
                browserManager.copyCurrentURL()
            case .hardReload:
                browserManager.hardReloadCurrentPage()
            case .muteUnmuteAudio:
                browserManager.toggleMuteCurrentTabInActiveWindow()
            case .customizeSpaceGradient:
                browserManager.showGradientEditor()
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
