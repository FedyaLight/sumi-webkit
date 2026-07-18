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
    private let currentProfileAuthority: BrowserCurrentProfileAuthority
    private let defaultBrowserService: SumiDefaultBrowserService

    init(
        browserManager: BrowserManager,
        defaultBrowserService: SumiDefaultBrowserService
    ) {
        self.browserManager = browserManager
        self.currentProfileAuthority = browserManager.currentProfileAuthority
        self.defaultBrowserService = defaultBrowserService
    }

    var currentProfile: Profile? {
        currentProfileAuthority.currentProfile
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
        browserManager?.spaceStateOwner.currentSpace != nil
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

    func createIncognitoWindow() {
        browserManager?.windowCommands.createIncognitoWindow()
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

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        browserManager?.windowSessionBundle.sessionRecovery.reopenRecentlyClosedItem(item)
    }

    func reopenAllWindowsFromLastSession() {
        browserManager?.windowSessionBundle.sessionRecovery.reopenAllWindowsFromLastSession()
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        browserManager?.historyBundle.historyNavigationOwner.openHistoryURLFromMenuItem(url)
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
