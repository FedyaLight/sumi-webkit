import AppKit
import SumiDomain

/// Adapts keyboard-shortcut actions to the browser owners that execute them.
/// Replaces the former god-object conformance of `BrowserManager` to
/// `ShortcutActionRouting` / `KeyboardShortcutChromeRouting`.
@MainActor
final class BrowserShortcutActionRouter {
    struct Dependencies {
        let keyboardShortcuts: @MainActor () -> BrowserKeyboardShortcutCommandOwner?
        let historyNavigation: @MainActor () -> BrowserHistoryNavigationOwner?
        let activePageResolver: @MainActor () -> ActivePageResolver?
        let activePageCommands: @MainActor () -> ActivePageCommandService?
        let zoomCommands: @MainActor () -> BrowserZoomCommandOwner?
        let windowShellCommands: @MainActor () -> BrowserWindowCommands?
        let pagePrivacyCommands: @MainActor () -> BrowserChromeCommands?
        let chromePopovers: @MainActor () -> BrowserChromeCommands?
        let dialogs: @MainActor () -> BrowserNativeDialogPresentationOwner?
        let sessionRecovery: @MainActor () -> BrowserSessionRecoveryCommands?
        let themeEditor: @MainActor () -> BrowserWorkspaceThemeEditorOwner?
        let floatingBarPresentation: @MainActor () -> FloatingBarPresentationService?
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
        dependencies.activePageCommands()?.reloadActivePage()
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
        dependencies.sessionRecovery()?.reopenMostRecentClosedItem()
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
        dependencies.activePageCommands()?.inspectActivePage()
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
        dependencies.activePageResolver()?.resolveActiveWindow()?.url
    }

    func focusFloatingBarForActiveWindow(prefill: String, navigateCurrentTab: Bool) {
        dependencies.floatingBarPresentation()?.focusActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            reason: .keyboard
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
        dependencies.activePageCommands()?.copyActivePageURL()
    }

    func hardReloadCurrentPage() {
        dependencies.pagePrivacyCommands()?.hardReloadCurrentPage()
    }

    func toggleReaderModeInActiveWindow() {
        dependencies.keyboardShortcuts()?.toggleReaderModeInActiveWindow()
    }

    func toggleMuteCurrentTabInActiveWindow() {
        dependencies.activePageCommands()?.toggleMuteForActivePage()
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
        dependencies.floatingBarPresentation()?.dismiss(
            in: windowState,
            preserveDraft: preserveDraft,
            cancelEmptySplitPlaceholder: true
        )
    }
}

extension BrowserShortcutActionRouter.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        // Keyboard-shortcut command handling has exactly one consumer — this
        // router — so the router owns the handler instead of resolving it
        // back through a BrowserManager façade property.
        let keyboardShortcuts = BrowserKeyboardShortcutCommandOwner(
            browserManager: browserManager
        )
        return Self(
            keyboardShortcuts: { keyboardShortcuts },
            historyNavigation: { [weak browserManager] in
                browserManager?.historyBundle.historyNavigationOwner
            },
            activePageResolver: { [weak browserManager] in
                browserManager?.shellRuntime.activePageResolver
            },
            activePageCommands: { [weak browserManager] in
                browserManager?.chromeBundle.activePageCommands
            },
            zoomCommands: { [weak browserManager] in
                browserManager?.chromeBundle.zoomCommandOwner
            },
            windowShellCommands: { [weak browserManager] in
                browserManager?.windowCommands
            },
            pagePrivacyCommands: { [weak browserManager] in
                browserManager?.chromeBundle.commands
            },
            chromePopovers: { [weak browserManager] in
                browserManager?.chromeBundle.commands
            },
            dialogs: { [weak browserManager] in
                browserManager?.chromeBundle.nativeDialogPresentationOwner
            },
            sessionRecovery: { [weak browserManager] in
                browserManager?.windowSessionBundle.sessionRecovery
            },
            themeEditor: { [weak browserManager] in
                browserManager?.chromeBundle.workspaceThemeEditorOwner
            },
            floatingBarPresentation: { [weak browserManager] in
                browserManager?.urlBarBundle.floatingBar.presentation
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
                browserManager?.chromeBundle.sidebarPresentationOwner.toggleSidebar()
            }
        )
    }
}
