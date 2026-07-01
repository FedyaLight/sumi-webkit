import AppKit

/// Adapts keyboard-shortcut actions to the browser owners that execute them.
/// Replaces the former god-object conformance of `BrowserManager` to
/// `ShortcutActionRouting` / `KeyboardShortcutChromeRouting`.
@MainActor
final class BrowserShortcutActionRouter {
    struct Dependencies {
        let keyboardShortcuts: @MainActor () -> BrowserKeyboardShortcutCommandOwner?
        let historyNavigation: @MainActor () -> BrowserHistoryNavigationOwner?
        let activePageRouting: @MainActor () -> BrowserActivePageRoutingOwner?
        let zoomCommands: @MainActor () -> BrowserZoomCommandOwner?
        let windowShellCommands: @MainActor () -> BrowserWindowShellCommandOwner?
        let pagePrivacyCommands: @MainActor () -> BrowserPagePrivacyCommandOwner?
        let chromePopovers: @MainActor () -> BrowserChromePopoverRoutingOwner?
        let dialogs: @MainActor () -> BrowserNativeDialogPresentationOwner?
        let recentlyClosedRestore: @MainActor () -> BrowserRecentlyClosedRestoreOwner?
        let themeEditor: @MainActor () -> BrowserWorkspaceThemeEditorOwner?
        let floatingBarRouting: @MainActor () -> BrowserFloatingBarRoutingOwner?
        let findManager: @MainActor () -> FindManager?
        let showFindBar: @MainActor () -> Void
        let closeCurrentTab: @MainActor () -> Void
        let duplicateCurrentTab: @MainActor () -> Void
        let toggleSidebar: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }
}

extension BrowserShortcutActionRouter: ShortcutActionRouting {
    func showFindBar() {
        dependencies.showFindBar()
    }

    func goBackInActiveWindow() {
        dependencies.historyNavigation()?.goBackInActiveWindow()
    }

    func goForwardInActiveWindow() {
        dependencies.historyNavigation()?.goForwardInActiveWindow()
    }

    func refreshCurrentTabInActiveWindow() {
        dependencies.activePageRouting()?.refreshCurrentTabInActiveWindow()
    }

    func clearCurrentPageCookies() {
        dependencies.pagePrivacyCommands()?.clearCurrentPageCookies()
    }

    func openNewTabSurfaceInActiveWindow() {
        dependencies.keyboardShortcuts()?.openNewTabSurfaceInActiveWindow()
    }

    func closeCurrentTab() {
        dependencies.closeCurrentTab()
    }

    func undoCloseTab() {
        dependencies.recentlyClosedRestore()?.reopenMostRecentClosedItem()
    }

    func selectNextTabInActiveWindow() {
        dependencies.keyboardShortcuts()?.selectNextTabInActiveWindow()
    }

    func selectPreviousTabInActiveWindow() {
        dependencies.keyboardShortcuts()?.selectPreviousTabInActiveWindow()
    }

    func selectTabByIndexInActiveWindow(_ index: Int) {
        dependencies.keyboardShortcuts()?.selectTabByIndexInActiveWindow(index)
    }

    func selectLastTabInActiveWindow() {
        dependencies.keyboardShortcuts()?.selectLastTabInActiveWindow()
    }

    func duplicateCurrentTab() {
        dependencies.duplicateCurrentTab()
    }

    func setActiveSplitLayout(_ layoutKind: SplitLayoutKind) {
        dependencies.keyboardShortcuts()?.setActiveSplitLayout(layoutKind)
    }

    func unsplitActiveWindow() {
        dependencies.keyboardShortcuts()?.unsplitActiveWindow()
    }

    func createEmptySplitInActiveWindow() {
        dependencies.keyboardShortcuts()?.createEmptySplitInActiveWindow()
    }

    func selectNextSpaceInActiveWindow() {
        dependencies.keyboardShortcuts()?.selectNextSpaceInActiveWindow()
    }

    func selectPreviousSpaceInActiveWindow() {
        dependencies.keyboardShortcuts()?.selectPreviousSpaceInActiveWindow()
    }

    func createNewWindow() {
        dependencies.windowShellCommands()?.createNewWindow()
    }

    func closeActiveWindow() {
        dependencies.windowShellCommands()?.closeActiveWindow()
    }

    func showQuitDialog() {
        dependencies.dialogs()?.showQuitDialog()
    }

    func toggleFullScreenForActiveWindow() {
        dependencies.windowShellCommands()?.toggleFullScreenForActiveWindow()
    }

    func openWebInspector() {
        dependencies.activePageRouting()?.openWebInspector()
    }

    func showDownloads() {
        dependencies.chromePopovers()?.showDownloads()
    }

    func showHistory() {
        dependencies.historyNavigation()?.openHistoryTab()
    }

    func expandAllFoldersInSidebar() {
        dependencies.keyboardShortcuts()?.expandAllFoldersInSidebar()
    }

    func activePageURLForActiveWindow() -> URL? {
        dependencies.activePageRouting()?.activePageURLForActiveWindow()
    }

    func focusFloatingBarForActiveWindow(prefill: String, navigateCurrentTab: Bool) {
        dependencies.floatingBarRouting()?.focusFloatingBarForActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: .keyboard
        )
    }

    func zoomInCurrentTab() {
        dependencies.zoomCommands()?.zoomInCurrentTab()
    }

    func zoomOutCurrentTab() {
        dependencies.zoomCommands()?.zoomOutCurrentTab()
    }

    func resetZoomCurrentTab() {
        dependencies.zoomCommands()?.resetZoomCurrentTab()
    }

    func toggleSidebar() {
        dependencies.toggleSidebar()
    }

    func copyCurrentURL() {
        dependencies.activePageRouting()?.copyCurrentURL()
    }

    func hardReloadCurrentPage() {
        dependencies.pagePrivacyCommands()?.hardReloadCurrentPage()
    }

    func toggleReaderModeInActiveWindow() {
        dependencies.keyboardShortcuts()?.toggleReaderModeInActiveWindow()
    }

    func toggleMuteCurrentTabInActiveWindow() {
        dependencies.activePageRouting()?.toggleMuteCurrentTabInActiveWindow()
    }

    func showGradientEditor() {
        dependencies.themeEditor()?.showGradientEditor()
    }
}

extension BrowserShortcutActionRouter: KeyboardShortcutChromeRouting {
    var isFindBarVisibleForShortcutRouting: Bool {
        dependencies.findManager()?.isFindBarVisible ?? false
    }

    func hideFindBarForShortcutRouting() {
        dependencies.findManager()?.hideFindBar()
    }

    func isNativeModalPresentedForShortcutRouting(in window: NSWindow) -> Bool {
        dependencies.dialogs()?.isNativeModalPresented(in: window) ?? false
    }

    func dismissFloatingBarForShortcutRouting(in windowState: BrowserWindowState, preserveDraft: Bool) {
        dependencies.floatingBarRouting()?.dismissFloatingBar(
            in: windowState,
            preserveDraft: preserveDraft,
            cancelEmptySplitPlaceholder: true
        )
    }
}

extension BrowserShortcutActionRouter.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            keyboardShortcuts: { [weak browserManager] in
                browserManager?.keyboardShortcutCommandOwner
            },
            historyNavigation: { [weak browserManager] in
                browserManager?.historyNavigationOwner
            },
            activePageRouting: { [weak browserManager] in
                browserManager?.activePageRoutingOwner
            },
            zoomCommands: { [weak browserManager] in
                browserManager?.zoomCommandOwner
            },
            windowShellCommands: { [weak browserManager] in
                browserManager?.windowShellCommandOwner
            },
            pagePrivacyCommands: { [weak browserManager] in
                browserManager?.pagePrivacyCommandOwner
            },
            chromePopovers: { [weak browserManager] in
                browserManager?.chromePopoverRoutingOwner
            },
            dialogs: { [weak browserManager] in
                browserManager?.nativeDialogPresentationOwner
            },
            recentlyClosedRestore: { [weak browserManager] in
                browserManager?.recentlyClosedRestoreOwner
            },
            themeEditor: { [weak browserManager] in
                browserManager?.workspaceThemeEditorOwner
            },
            floatingBarRouting: { [weak browserManager] in
                browserManager?.floatingBarRoutingOwner
            },
            findManager: { [weak browserManager] in
                browserManager?.findManager
            },
            showFindBar: { [weak browserManager] in
                browserManager?.showFindBar()
            },
            closeCurrentTab: { [weak browserManager] in
                browserManager?.tabLifecycleService.closeOrchestration.closeCurrentTab()
            },
            duplicateCurrentTab: { [weak browserManager] in
                browserManager?.duplicateCurrentTab()
            },
            toggleSidebar: { [weak browserManager] in
                browserManager?.toggleSidebar()
            }
        )
    }
}
