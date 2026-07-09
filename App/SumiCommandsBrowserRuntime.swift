import Foundation

@MainActor
extension SumiCommandsBrowserRuntime {
    static func live(
        browserManager: BrowserManager,
        defaultBrowserService: SumiDefaultBrowserService
    ) -> SumiCommandsBrowserRuntime {
        let adapter = SumiCommandsBrowserManagerAdapter(
            browserManager: browserManager,
            defaultBrowserService: defaultBrowserService
        )
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
    private let defaultBrowserService: SumiDefaultBrowserService

    init(
        browserManager: BrowserManager,
        defaultBrowserService: SumiDefaultBrowserService
    ) {
        self.browserManager = browserManager
        self.defaultBrowserService = defaultBrowserService
    }

    var currentProfile: Profile? {
        browserManager?.currentProfile
    }

    func activePageTabForActiveWindow() -> Tab? {
        browserManager?.urlBarBundle.activePageRoutingOwner.activePageTabForActiveWindow()
    }

    func activePageURLForActiveWindow() -> URL? {
        browserManager?.urlBarBundle.activePageRoutingOwner.activePageURLForActiveWindow()
    }

    func currentTabIsMuted() -> Bool {
        browserManager?.urlBarBundle.activePageRoutingOwner.currentTabIsMuted() ?? false
    }

    func currentTabHasAudioContent() -> Bool {
        browserManager?.urlBarBundle.activePageRoutingOwner.currentTabHasAudioContent() ?? false
    }

    func hasCustomizableSpaceForCommands() -> Bool {
        browserManager?.tabManager.spaceStateOwner.currentSpace != nil
    }

    func openSettingsTab(selecting pane: SettingsTabs, in windowState: BrowserWindowState?) {
        browserManager?.urlBarBundle.commands.openSettingsTab(selecting: pane, in: windowState)
    }

    func setAsDefaultBrowser() {
        let defaultBrowserService = defaultBrowserService
        Task {
            _ = await defaultBrowserService.requestBecomeDefault()
        }
    }

    func clearCurrentPageCookies() {
        browserManager?.chromeBundle.commands.clearCurrentPageCookies()
    }

    func showGradientEditor() {
        browserManager?.chromeBundle.workspaceThemeEditorOwner.showGradientEditor()
    }

    func showQuitDialog() {
        browserManager?.chromeBundle.nativeDialogPresentationOwner.showQuitDialog()
    }

    func closeCurrentTab() {
        browserManager?.tabLifecycleService.closeOrchestration.closeCurrentTab()
    }

    func closeCurrentTab(in windowState: BrowserWindowState) {
        browserManager?.tabLifecycleService.closeOrchestration.closeCurrentTab(in: windowState)
    }

    func closeActiveWindow() {
        browserManager?.windowSessionBundle.commands.closeActiveWindow()
    }

    func closeWindow(_ windowState: BrowserWindowState) {
        browserManager?.windowSessionBundle.commands.closeWindow(windowState)
    }

    func undoCloseTab() {
        browserManager?.windowSessionBundle.recentlyClosedRestoreOwner.reopenMostRecentClosedItem()
    }

    func openNewTabSurfaceInActiveWindow() {
        browserManager?.keyboardShortcutCommandOwner.openNewTabSurfaceInActiveWindow()
    }

    func createNewWindow() {
        browserManager?.windowSessionBundle.commands.createNewWindow()
    }

    func createIncognitoWindow() {
        browserManager?.windowSessionBundle.commands.createIncognitoWindow()
    }

    func focusFloatingBarForActiveWindow(
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason
    ) {
        browserManager?.urlBarBundle.floatingBarRoutingOwner.focusFloatingBarForActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason
        )
    }

    func copyCurrentURL() {
        browserManager?.urlBarBundle.activePageRoutingOwner.copyCurrentURL()
    }

    func toggleSidebar() {
        browserManager?.chromeBundle.sidebarPresentationOwner.toggleSidebar()
    }

    func showFindBar() {
        browserManager?.showFindBar()
    }

    func refreshCurrentTabInActiveWindow() {
        browserManager?.urlBarBundle.activePageRoutingOwner.refreshCurrentTabInActiveWindow()
    }

    func zoomInCurrentTab() {
        browserManager?.chromeBundle.zoomCommandOwner.zoomInCurrentTab()
    }

    func zoomOutCurrentTab() {
        browserManager?.chromeBundle.zoomCommandOwner.zoomOutCurrentTab()
    }

    func resetZoomCurrentTab() {
        browserManager?.chromeBundle.zoomCommandOwner.resetZoomCurrentTab()
    }

    func hardReloadCurrentPage() {
        browserManager?.chromeBundle.commands.hardReloadCurrentPage()
    }

    func openWebInspector() {
        browserManager?.urlBarBundle.activePageRoutingOwner.openWebInspector()
    }

    func toggleMuteCurrentTabInActiveWindow() {
        browserManager?.urlBarBundle.activePageRoutingOwner.toggleMuteCurrentTabInActiveWindow()
    }

    var canGoBackInActiveWindow: Bool {
        browserManager?.historyBundle.historyNavigationOwner.canGoBackInActiveWindow ?? false
    }

    var canGoForwardInActiveWindow: Bool {
        browserManager?.historyBundle.historyNavigationOwner.canGoForwardInActiveWindow ?? false
    }

    var canRestoreAnyLastSession: Bool {
        browserManager?.windowSessionBundle.recentlyClosedRestoreOwner.canRestoreAnyLastSession ?? false
    }

    func goBackInActiveWindow() {
        browserManager?.historyBundle.historyNavigationOwner.goBackInActiveWindow()
    }

    func goForwardInActiveWindow() {
        browserManager?.historyBundle.historyNavigationOwner.goForwardInActiveWindow()
    }

    func reopenMostRecentClosedItem() {
        browserManager?.windowSessionBundle.recentlyClosedRestoreOwner.reopenMostRecentClosedItem()
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        browserManager?.windowSessionBundle.recentlyClosedRestoreOwner.reopenRecentlyClosedItem(item)
    }

    func reopenAllWindowsFromLastSession() {
        browserManager?.windowSessionBundle.recentlyClosedRestoreOwner.reopenAllWindowsFromLastSession()
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        browserManager?.historyBundle.historyNavigationOwner.openHistoryURLFromMenuItem(url)
    }

    func showHistory() {
        browserManager?.historyBundle.historyNavigationOwner.openHistoryTab()
    }

    func clearAllHistoryFromMenu() {
        browserManager?.historyBundle.historyMenuOwner.clearAllHistoryFromMenu()
    }

    func canBookmarkAllTabsInActiveWindow() -> Bool {
        browserManager?.bookmarkBundle.bookmarkCommandOwner.canBookmarkAllTabsInActiveWindow() ?? false
    }

    func requestBookmarkEditorForActiveWindowFromMenu() {
        browserManager?.bookmarkBundle.bookmarkCommandOwner.requestBookmarkEditorForActiveWindowFromMenu()
    }

    func bookmarkAllTabsFromMenu() {
        browserManager?.bookmarkBundle.bookmarkCommandOwner.bookmarkAllTabsFromMenu()
    }

    func manageBookmarksFromMenu() {
        browserManager?.bookmarkBundle.bookmarkCommandOwner.manageBookmarksFromMenu()
    }

    func importBookmarksFromMenu() {
        browserManager?.bookmarkBundle.bookmarkCommandOwner.importBookmarksFromMenu()
    }

    func exportBookmarksFromMenu() {
        browserManager?.bookmarkBundle.bookmarkCommandOwner.exportBookmarksFromMenu()
    }

    func openBookmarkURLFromMenuItem(_ url: URL) {
        browserManager?.bookmarkBundle.bookmarkCommandOwner.openBookmarkURLFromMenuItem(url)
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
