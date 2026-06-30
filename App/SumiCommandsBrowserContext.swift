import Foundation

@MainActor
final class SumiCommandsBrowserContext {
    private weak var browserManager: BrowserManager?

    let recentlyClosedManager: RecentlyClosedManager
    let historyManager: HistoryManager
    let bookmarkManager: SumiBookmarkManager
    let faviconService: any BrowserFaviconServicing

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
        self.recentlyClosedManager = browserManager.recentlyClosedManager
        self.historyManager = browserManager.historyManager
        self.bookmarkManager = browserManager.bookmarkManager
        self.faviconService = browserManager.dataServices.faviconService
    }

    var currentProfile: Profile? {
        browserManager?.currentProfile
    }

    var faviconPartition: SumiFaviconPartition {
        faviconService.partition(profile: currentProfile)
    }

    var activePageTab: Tab? {
        browserManager?.activePageTabForActiveWindow()
    }

    var activePageURL: URL? {
        browserManager?.activePageURLForActiveWindow()
    }

    var activePageHost: String? {
        activePageURL?.host
    }

    var hasActivePageTab: Bool {
        activePageTab != nil
    }

    var canReloadActivePage: Bool {
        guard let activePageTab else { return false }
        return activePageTab.representsSumiNativeSurface == false
    }

    var canCustomizeSpaceGradient: Bool {
        browserManager?.tabManager.currentSpace != nil
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

    var canBookmarkActivePage: Bool {
        bookmarkManager.canBookmark(activePageTab)
    }

    var canBookmarkAllTabsInActiveWindow: Bool {
        browserManager?.canBookmarkAllTabsInActiveWindow() ?? false
    }

    var currentTabIsMuted: Bool {
        browserManager?.currentTabIsMuted() ?? false
    }

    var currentTabHasAudioContent: Bool {
        browserManager?.currentTabHasAudioContent() ?? false
    }

#if DEBUG
    var extensionsDiagnosticsAreEnabled: Bool {
        browserManager?.extensionsModule.isEnabled == true
    }
#endif

    func openSettingsTab(selecting pane: SettingsTabs) {
        browserManager?.openSettingsTab(selecting: pane)
    }

    func setAsDefaultBrowser() {
        browserManager?.setAsDefaultBrowser()
    }

    func clearCurrentPageCookies() {
        browserManager?.clearCurrentPageCookies()
    }

    func clearAllHistoryFromMenu() {
        browserManager?.clearAllHistoryFromMenu()
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

    func closeActiveWindow() {
        browserManager?.closeActiveWindow()
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

    func focusFloatingBarForActiveWindow(prefill: String, navigateCurrentTab: Bool) {
        browserManager?.focusFloatingBarForActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab
        )
    }

    func openCommandBarForActivePage() {
        focusFloatingBarForActiveWindow(
            prefill: activePageURL?.absoluteString ?? "",
            navigateCurrentTab: true
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

#if DEBUG
    func printSafariExtensionAcceptanceCheckToConsole() {
        browserManager?.extensionsModule.printSafariExtensionAcceptanceCheckToConsole()
    }

    func printSafariExtensionNativeMessagingProbeToConsole() {
        browserManager?.extensionsModule.printSafariExtensionNativeMessagingProbeToConsole()
    }

    func printSafariExtensionDevDiagnosticsReportToConsole() {
        browserManager?.extensionsModule.printSafariExtensionDevDiagnosticsReportToConsole()
    }
#endif
}
