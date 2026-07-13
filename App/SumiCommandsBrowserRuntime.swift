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
            faviconImageReader: browserManager.dataServices.faviconCapabilities.images,
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
            faviconService: browserManager.dataServices.faviconService,
            faviconImageReader: browserManager.dataServices.faviconCapabilities.images
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
        browserManager?.shellRuntime.activePageResolver.resolveActiveWindow()?.tab
    }

    func activePageURLForActiveWindow() -> URL? {
        browserManager?.shellRuntime.activePageResolver.resolveActiveWindow()?.url
    }

    func currentTabIsMuted() -> Bool {
        guard let tab = browserManager?.shellRuntime.activePageResolver
            .resolveActiveWindow()?.tab,
              !tab.representsSumiNativeSurface
        else { return false }
        return tab.audioState.isMuted
    }

    func currentTabHasAudioContent() -> Bool {
        guard let tab = browserManager?.shellRuntime.activePageResolver
            .resolveActiveWindow()?.tab,
              !tab.representsSumiNativeSurface
        else { return false }
        return tab.audioState.isPlayingAudio
    }

    func hasCustomizableSpaceForCommands() -> Bool {
        browserManager?.tabManager.spaceStateOwner.currentSpace != nil
    }

    func openSettingsTab(selecting pane: SettingsTabs, in windowState: BrowserWindowState?) {
        browserManager?.urlBarBundle.settingsNavigation.openSettings(
            selecting: pane,
            in: windowState
        )
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
        browserManager?.windowCommands.closeActiveWindow()
    }

    func closeWindow(_ windowState: BrowserWindowState) {
        browserManager?.windowCommands.closeWindow(windowState)
    }

    func undoCloseTab() {
        browserManager?.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()
    }

    func openNewTabSurfaceInActiveWindow() {
        // Menu "new tab" executes through the same shortcut-action routing
        // surface as the keyboard shortcut, which owns the command handler.
        browserManager?.shortcutActionRouter.openNewTabSurfaceInActiveWindow()
    }

    func createNewWindow() {
        browserManager?.windowCommands.createNewWindow()
    }

    func createIncognitoWindow() {
        browserManager?.windowCommands.createIncognitoWindow()
    }

    func focusFloatingBarForActiveWindow(
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason
    ) {
        browserManager?.urlBarBundle.floatingBar.presentation.focusActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            reason: presentationReason
        )
    }

    func copyCurrentURL() {
        browserManager?.chromeBundle.activePageCommands.copyActivePageURL()
    }

    func toggleSidebar() {
        browserManager?.chromeBundle.sidebarPresentationOwner.toggleSidebar()
    }

    func showFindBar() {
        browserManager?.showFindBar()
    }

    func refreshCurrentTabInActiveWindow() {
        browserManager?.chromeBundle.activePageCommands.reloadActivePage()
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
        browserManager?.chromeBundle.activePageCommands.inspectActivePage()
    }

    func toggleMuteCurrentTabInActiveWindow() {
        browserManager?.chromeBundle.activePageCommands.toggleMuteForActivePage()
    }

    var canGoBackInActiveWindow: Bool {
        browserManager?.historyBundle.historyNavigationOwner.canGoBackInActiveWindow ?? false
    }

    var canGoForwardInActiveWindow: Bool {
        browserManager?.historyBundle.historyNavigationOwner.canGoForwardInActiveWindow ?? false
    }

    var canRestoreAnyLastSession: Bool {
        browserManager?.windowSessionBundle.sessionRecovery.canRestoreAnyLastSession ?? false
    }

    func goBackInActiveWindow() {
        browserManager?.historyBundle.historyNavigationOwner.goBackInActiveWindow()
    }

    func goForwardInActiveWindow() {
        browserManager?.historyBundle.historyNavigationOwner.goForwardInActiveWindow()
    }

    func reopenMostRecentClosedItem() {
        browserManager?.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        browserManager?.windowSessionBundle.sessionRecovery.reopenRecentlyClosedItem(item)
    }

    func reopenAllWindowsFromLastSession() {
        browserManager?.windowSessionBundle.sessionRecovery.reopenAllWindowsFromLastSession()
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        browserManager?.historyBundle.historyNavigationOwner.openHistoryURLFromMenuItem(url)
    }

    func showHistory() {
        browserManager?.historyBundle.historyNavigationOwner.openHistoryTab()
    }

    func clearAllHistoryFromMenu() {
        browserManager?.historyBundle.clearHistory.execute()
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
        browserManager?.optionalModules.extensions.isEnabled == true
    }

    func printSafariExtensionAcceptanceCheckToConsole() {
        browserManager?.optionalModules.extensions.printSafariExtensionAcceptanceCheckToConsole()
    }

    func printSafariExtensionNativeMessagingProbeToConsole() {
        browserManager?.optionalModules.extensions.printSafariExtensionNativeMessagingProbeToConsole()
    }

    func printSafariExtensionDevDiagnosticsReportToConsole() {
        browserManager?.optionalModules.extensions.printSafariExtensionDevDiagnosticsReportToConsole()
    }
}
#endif
