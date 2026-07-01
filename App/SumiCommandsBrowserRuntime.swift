import Foundation

@MainActor
extension SumiCommandsBrowserRuntime {
    static func live(browserManager: BrowserManager) -> SumiCommandsBrowserRuntime {
        let adapter = SumiCommandsBrowserManagerAdapter(browserManager: browserManager)
#if DEBUG
        return SumiCommandsBrowserRuntime(
            pageState: adapter,
            browserActions: adapter,
            historyRouting: adapter,
            bookmarkRouting: adapter,
            recentlyClosedManager: browserManager.recentlyClosedManager,
            historyManager: browserManager.historyManager,
            bookmarkManager: browserManager.bookmarkManager,
            faviconService: browserManager.dataServices.faviconService,
            extensionDiagnostics: adapter
        )
#else
        return SumiCommandsBrowserRuntime(
            pageState: adapter,
            browserActions: adapter,
            historyRouting: adapter,
            bookmarkRouting: adapter,
            recentlyClosedManager: browserManager.recentlyClosedManager,
            historyManager: browserManager.historyManager,
            bookmarkManager: browserManager.bookmarkManager,
            faviconService: browserManager.dataServices.faviconService
        )
#endif
    }
}

@MainActor
private final class SumiCommandsBrowserManagerAdapter:
    SumiCommandPageStateProviding,
    SumiCommandBrowserActionRouting,
    SumiCommandHistoryRouting,
    SumiCommandBookmarkRouting {
    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    var currentProfile: Profile? {
        browserManager?.currentProfile
    }

    func activePageTabForActiveWindow() -> Tab? {
        browserManager?.activePageRoutingOwner.activePageTabForActiveWindow()
    }

    func activePageURLForActiveWindow() -> URL? {
        browserManager?.activePageRoutingOwner.activePageURLForActiveWindow()
    }

    func currentTabIsMuted() -> Bool {
        browserManager?.activePageRoutingOwner.currentTabIsMuted() ?? false
    }

    func currentTabHasAudioContent() -> Bool {
        browserManager?.activePageRoutingOwner.currentTabHasAudioContent() ?? false
    }

    func hasCustomizableSpaceForCommands() -> Bool {
        browserManager?.tabManager.currentSpace != nil
    }

    func openSettingsTab(selecting pane: SettingsTabs, in windowState: BrowserWindowState?) {
        browserManager?.openSettingsTab(selecting: pane, in: windowState)
    }

    func setAsDefaultBrowser() {
        Task {
            _ = await SumiDefaultBrowserService.shared.requestBecomeDefault()
        }
    }

    func clearCurrentPageCookies() {
        browserManager?.pagePrivacyCommandOwner.clearCurrentPageCookies()
    }

    func showGradientEditor() {
        browserManager?.workspaceThemeEditorOwner.showGradientEditor()
    }

    func showQuitDialog() {
        browserManager?.nativeDialogPresentationOwner.showQuitDialog()
    }

    func closeCurrentTab() {
        browserManager?.closeCurrentTab()
    }

    func closeCurrentTab(in windowState: BrowserWindowState) {
        browserManager?.closeCurrentTab(in: windowState)
    }

    func closeActiveWindow() {
        browserManager?.windowShellCommandOwner.closeActiveWindow()
    }

    func closeWindow(_ windowState: BrowserWindowState) {
        browserManager?.windowShellCommandOwner.closeWindow(windowState)
    }

    func undoCloseTab() {
        browserManager?.recentlyClosedRestoreOwner.reopenMostRecentClosedItem()
    }

    func openNewTabSurfaceInActiveWindow() {
        browserManager?.keyboardShortcutCommandOwner.openNewTabSurfaceInActiveWindow()
    }

    func createNewWindow() {
        browserManager?.windowShellCommandOwner.createNewWindow()
    }

    func createIncognitoWindow() {
        browserManager?.windowShellCommandOwner.createIncognitoWindow()
    }

    func focusFloatingBarForActiveWindow(
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason
    ) {
        browserManager?.floatingBarRoutingOwner.focusFloatingBarForActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason
        )
    }

    func copyCurrentURL() {
        browserManager?.activePageRoutingOwner.copyCurrentURL()
    }

    func toggleSidebar() {
        browserManager?.toggleSidebar()
    }

    func showFindBar() {
        browserManager?.showFindBar()
    }

    func refreshCurrentTabInActiveWindow() {
        browserManager?.activePageRoutingOwner.refreshCurrentTabInActiveWindow()
    }

    func zoomInCurrentTab() {
        browserManager?.zoomCommandOwner.zoomInCurrentTab()
    }

    func zoomOutCurrentTab() {
        browserManager?.zoomCommandOwner.zoomOutCurrentTab()
    }

    func resetZoomCurrentTab() {
        browserManager?.zoomCommandOwner.resetZoomCurrentTab()
    }

    func hardReloadCurrentPage() {
        browserManager?.pagePrivacyCommandOwner.hardReloadCurrentPage()
    }

    func openWebInspector() {
        browserManager?.activePageRoutingOwner.openWebInspector()
    }

    func toggleMuteCurrentTabInActiveWindow() {
        browserManager?.activePageRoutingOwner.toggleMuteCurrentTabInActiveWindow()
    }

    var canGoBackInActiveWindow: Bool {
        browserManager?.historyNavigationOwner.canGoBackInActiveWindow ?? false
    }

    var canGoForwardInActiveWindow: Bool {
        browserManager?.historyNavigationOwner.canGoForwardInActiveWindow ?? false
    }

    var canRestoreAnyLastSession: Bool {
        browserManager?.recentlyClosedRestoreOwner.canRestoreAnyLastSession ?? false
    }

    func goBackInActiveWindow() {
        browserManager?.historyNavigationOwner.goBackInActiveWindow()
    }

    func goForwardInActiveWindow() {
        browserManager?.historyNavigationOwner.goForwardInActiveWindow()
    }

    func reopenMostRecentClosedItem() {
        browserManager?.recentlyClosedRestoreOwner.reopenMostRecentClosedItem()
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        browserManager?.recentlyClosedRestoreOwner.reopenRecentlyClosedItem(item)
    }

    func reopenAllWindowsFromLastSession() {
        browserManager?.recentlyClosedRestoreOwner.reopenAllWindowsFromLastSession()
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        browserManager?.historyNavigationOwner.openHistoryURLFromMenuItem(url)
    }

    func showHistory() {
        browserManager?.historyNavigationOwner.openHistoryTab()
    }

    func clearAllHistoryFromMenu() {
        browserManager?.historyMenuOwner.clearAllHistoryFromMenu()
    }

    func canBookmarkAllTabsInActiveWindow() -> Bool {
        browserManager?.bookmarkCommandOwner.canBookmarkAllTabsInActiveWindow() ?? false
    }

    func requestBookmarkEditorForActiveWindowFromMenu() {
        browserManager?.bookmarkCommandOwner.requestBookmarkEditorForActiveWindowFromMenu()
    }

    func bookmarkAllTabsFromMenu() {
        browserManager?.bookmarkCommandOwner.bookmarkAllTabsFromMenu()
    }

    func manageBookmarksFromMenu() {
        browserManager?.bookmarkCommandOwner.manageBookmarksFromMenu()
    }

    func importBookmarksFromMenu() {
        browserManager?.bookmarkCommandOwner.importBookmarksFromMenu()
    }

    func exportBookmarksFromMenu() {
        browserManager?.bookmarkCommandOwner.exportBookmarksFromMenu()
    }

    func openBookmarkURLFromMenuItem(_ url: URL) {
        browserManager?.bookmarkCommandOwner.openBookmarkURLFromMenuItem(url)
    }
}

#if DEBUG
extension SumiCommandsBrowserManagerAdapter: SumiCommandExtensionDiagnosticsRouting {
    var extensionDiagnosticsEnabledForCommands: Bool {
        browserManager?.extensionsModule.isEnabled == true
    }

    func printSafariExtensionAcceptanceCheckToConsole() {
        browserManager?.extensionsModule.printSafariExtensionAcceptanceCheckToConsole()
    }

    func printSafariExtensionNativeMessagingProbeToConsole() {
        browserManager?.extensionsModule.printSafariExtensionNativeMessagingProbeToConsole()
    }

    func printSafariExtensionDevDiagnosticsReportToConsole() {
        browserManager?.extensionsModule.printSafariExtensionDevDiagnosticsReportToConsole()
    }
}
#endif
