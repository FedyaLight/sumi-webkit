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
        browserManager?.activePageTabForActiveWindow()
    }

    func activePageURLForActiveWindow() -> URL? {
        browserManager?.activePageURLForActiveWindow()
    }

    func currentTabIsMuted() -> Bool {
        browserManager?.currentTabIsMuted() ?? false
    }

    func currentTabHasAudioContent() -> Bool {
        browserManager?.currentTabHasAudioContent() ?? false
    }

    func hasCustomizableSpaceForCommands() -> Bool {
        browserManager?.tabManager.currentSpace != nil
    }

    func openSettingsTab(selecting pane: SettingsTabs, in windowState: BrowserWindowState?) {
        browserManager?.openSettingsTab(selecting: pane, in: windowState)
    }

    func setAsDefaultBrowser() {
        browserManager?.setAsDefaultBrowser()
    }

    func clearCurrentPageCookies() {
        browserManager?.clearCurrentPageCookies()
    }

    func showGradientEditor() {
        browserManager?.showGradientEditor()
    }

    func showQuitDialog() {
        browserManager?.showQuitDialog()
    }

    func closeCurrentTab() {
        browserManager?.closeCurrentTab()
    }

    func closeCurrentTab(in windowState: BrowserWindowState) {
        browserManager?.closeCurrentTab(in: windowState)
    }

    func closeActiveWindow() {
        browserManager?.closeActiveWindow()
    }

    func closeWindow(_ windowState: BrowserWindowState) {
        browserManager?.closeWindow(windowState)
    }

    func undoCloseTab() {
        browserManager?.undoCloseTab()
    }

    func openNewTabSurfaceInActiveWindow() {
        browserManager?.openNewTabSurfaceInActiveWindow()
    }

    func createNewWindow() {
        browserManager?.createNewWindow()
    }

    func createIncognitoWindow() {
        browserManager?.createIncognitoWindow()
    }

    func focusFloatingBarForActiveWindow(
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason
    ) {
        browserManager?.focusFloatingBarForActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason
        )
    }

    func copyCurrentURL() {
        browserManager?.copyCurrentURL()
    }

    func toggleSidebar() {
        browserManager?.toggleSidebar()
    }

    func showFindBar() {
        browserManager?.showFindBar()
    }

    func refreshCurrentTabInActiveWindow() {
        browserManager?.refreshCurrentTabInActiveWindow()
    }

    func zoomInCurrentTab() {
        browserManager?.zoomInCurrentTab()
    }

    func zoomOutCurrentTab() {
        browserManager?.zoomOutCurrentTab()
    }

    func resetZoomCurrentTab() {
        browserManager?.resetZoomCurrentTab()
    }

    func hardReloadCurrentPage() {
        browserManager?.hardReloadCurrentPage()
    }

    func openWebInspector() {
        browserManager?.openWebInspector()
    }

    func toggleMuteCurrentTabInActiveWindow() {
        browserManager?.toggleMuteCurrentTabInActiveWindow()
    }

    var canGoBackInActiveWindow: Bool {
        browserManager?.canGoBackInActiveWindow ?? false
    }

    var canGoForwardInActiveWindow: Bool {
        browserManager?.canGoForwardInActiveWindow ?? false
    }

    var canRestoreAnyLastSession: Bool {
        browserManager?.canRestoreAnyLastSession ?? false
    }

    func goBackInActiveWindow() {
        browserManager?.goBackInActiveWindow()
    }

    func goForwardInActiveWindow() {
        browserManager?.goForwardInActiveWindow()
    }

    func reopenMostRecentClosedItem() {
        browserManager?.reopenMostRecentClosedItem()
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        browserManager?.reopenRecentlyClosedItem(item)
    }

    func reopenAllWindowsFromLastSession() {
        browserManager?.reopenAllWindowsFromLastSession()
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        browserManager?.openHistoryURLFromMenuItem(url)
    }

    func showHistory() {
        browserManager?.showHistory()
    }

    func clearAllHistoryFromMenu() {
        browserManager?.clearAllHistoryFromMenu()
    }

    func canBookmarkAllTabsInActiveWindow() -> Bool {
        browserManager?.canBookmarkAllTabsInActiveWindow() ?? false
    }

    func requestBookmarkEditorForActiveWindowFromMenu() {
        browserManager?.requestBookmarkEditorForActiveWindowFromMenu()
    }

    func bookmarkAllTabsFromMenu() {
        browserManager?.bookmarkAllTabsFromMenu()
    }

    func manageBookmarksFromMenu() {
        browserManager?.manageBookmarksFromMenu()
    }

    func importBookmarksFromMenu() {
        browserManager?.importBookmarksFromMenu()
    }

    func exportBookmarksFromMenu() {
        browserManager?.exportBookmarksFromMenu()
    }

    func openBookmarkURLFromMenuItem(_ url: URL) {
        browserManager?.openBookmarkURLFromMenuItem(url)
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
