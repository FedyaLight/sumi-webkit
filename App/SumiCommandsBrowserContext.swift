import Foundation

@MainActor
protocol SumiCommandPageStateProviding: AnyObject {
    var currentProfile: Profile? { get }
    func activePageTabForActiveWindow() -> Tab?
    func activePageURLForActiveWindow() -> URL?
    func currentTabIsMuted() -> Bool
    func currentTabHasAudioContent() -> Bool
    func hasCustomizableSpaceForCommands() -> Bool
}

@MainActor
protocol SumiCommandBrowserActionRouting: AnyObject {
    func openSettingsTab(selecting pane: SettingsTabs, in windowState: BrowserWindowState?)
    func setAsDefaultBrowser()
    func clearCurrentPageCookies()
    func createIncognitoWindow()
}

@MainActor
protocol SumiCommandHistoryRouting: AnyObject {
    var canGoBackInActiveWindow: Bool { get }
    var canGoForwardInActiveWindow: Bool { get }
    var canRestoreAnyLastSession: Bool { get }
    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem)
    func reopenAllWindowsFromLastSession()
    func openHistoryURLFromMenuItem(_ url: URL)
    func clearAllHistoryFromMenu()
}

@MainActor
protocol SumiCommandBookmarkRouting: AnyObject {
    func canBookmarkAllTabsInActiveWindow() -> Bool
    func requestBookmarkEditorForActiveWindowFromMenu()
    func bookmarkAllTabsFromMenu()
    func manageBookmarksFromMenu()
    func importBookmarksFromMenu()
    func exportBookmarksFromMenu()
    func openBookmarkURLFromMenuItem(_ url: URL)
}

#if DEBUG
@MainActor
protocol SumiCommandExtensionDiagnosticsRouting: AnyObject {
    var extensionDiagnosticsEnabledForCommands: Bool { get }
    func printSafariExtensionAcceptanceCheckToConsole()
    func printSafariExtensionNativeMessagingProbeToConsole()
    func printSafariExtensionDevDiagnosticsReportToConsole()
}
#endif

@MainActor
struct SumiCommandsBrowserRuntime {
    let pageState: any SumiCommandPageStateProviding
    let browserActions: any SumiCommandBrowserActionRouting
    let historyRouting: any SumiCommandHistoryRouting
    let bookmarkRouting: any SumiCommandBookmarkRouting
    let recentlyClosedManager: RecentlyClosedManager
    let historyManager: HistoryManager
    let bookmarkManager: SumiBookmarkManager
    let faviconService: any BrowserFaviconServicing
    let faviconImageReader: any BrowserFaviconImageReading
#if DEBUG
    var extensionDiagnostics: (any SumiCommandExtensionDiagnosticsRouting)?
#endif
}

@MainActor
final class SumiCommandsBrowserContext {
    private let pageState: any SumiCommandPageStateProviding
    private let browserActions: any SumiCommandBrowserActionRouting
    private let historyRouting: any SumiCommandHistoryRouting
    private let bookmarkRouting: any SumiCommandBookmarkRouting
#if DEBUG
    private var extensionDiagnostics: (any SumiCommandExtensionDiagnosticsRouting)?
#endif

    let recentlyClosedManager: RecentlyClosedManager
    let historyManager: HistoryManager
    let bookmarkManager: SumiBookmarkManager
    let faviconService: any BrowserFaviconServicing
    let faviconImageReader: any BrowserFaviconImageReading

    init(runtime: SumiCommandsBrowserRuntime) {
        self.pageState = runtime.pageState
        self.browserActions = runtime.browserActions
        self.historyRouting = runtime.historyRouting
        self.bookmarkRouting = runtime.bookmarkRouting
        self.recentlyClosedManager = runtime.recentlyClosedManager
        self.historyManager = runtime.historyManager
        self.bookmarkManager = runtime.bookmarkManager
        self.faviconService = runtime.faviconService
        self.faviconImageReader = runtime.faviconImageReader
#if DEBUG
        self.extensionDiagnostics = runtime.extensionDiagnostics
#endif
    }

    init(
        pageState: any SumiCommandPageStateProviding,
        browserActions: any SumiCommandBrowserActionRouting,
        historyRouting: any SumiCommandHistoryRouting,
        bookmarkRouting: any SumiCommandBookmarkRouting,
        recentlyClosedManager: RecentlyClosedManager,
        historyManager: HistoryManager,
        bookmarkManager: SumiBookmarkManager,
        faviconService: any BrowserFaviconServicing,
        faviconImageReader: any BrowserFaviconImageReading
    ) {
        self.pageState = pageState
        self.browserActions = browserActions
        self.historyRouting = historyRouting
        self.bookmarkRouting = bookmarkRouting
        self.recentlyClosedManager = recentlyClosedManager
        self.historyManager = historyManager
        self.bookmarkManager = bookmarkManager
        self.faviconService = faviconService
        self.faviconImageReader = faviconImageReader
    }

    var currentProfile: Profile? {
        pageState.currentProfile
    }

    var faviconPartition: SumiFaviconPartition {
        faviconService.partition(profile: currentProfile)
    }

    var activePageTab: Tab? {
        pageState.activePageTabForActiveWindow()
    }

    var activePageURL: URL? {
        pageState.activePageURLForActiveWindow()
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
        pageState.hasCustomizableSpaceForCommands()
    }

    var canGoBackInActiveWindow: Bool {
        historyRouting.canGoBackInActiveWindow
    }

    var canGoForwardInActiveWindow: Bool {
        historyRouting.canGoForwardInActiveWindow
    }

    var canRestoreAnyLastSession: Bool {
        historyRouting.canRestoreAnyLastSession
    }

    var canBookmarkActivePage: Bool {
        bookmarkManager.canBookmark(activePageTab)
    }

    var canBookmarkAllTabsInActiveWindow: Bool {
        bookmarkRouting.canBookmarkAllTabsInActiveWindow()
    }

    var currentTabIsMuted: Bool {
        pageState.currentTabIsMuted()
    }

    var currentTabHasAudioContent: Bool {
        pageState.currentTabHasAudioContent()
    }

#if DEBUG
    var extensionsDiagnosticsAreEnabled: Bool {
        extensionDiagnostics?.extensionDiagnosticsEnabledForCommands == true
    }
#endif

    func openSettingsTab(selecting pane: SettingsTabs) {
        browserActions.openSettingsTab(selecting: pane, in: nil)
    }

    func setAsDefaultBrowser() {
        browserActions.setAsDefaultBrowser()
    }

    func clearCurrentPageCookies() {
        browserActions.clearCurrentPageCookies()
    }

    func clearAllHistoryFromMenu() {
        historyRouting.clearAllHistoryFromMenu()
    }

    func createIncognitoWindow() {
        browserActions.createIncognitoWindow()
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        historyRouting.reopenRecentlyClosedItem(item)
    }

    func reopenAllWindowsFromLastSession() {
        historyRouting.reopenAllWindowsFromLastSession()
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        historyRouting.openHistoryURLFromMenuItem(url)
    }

    func requestBookmarkEditorForActiveWindowFromMenu() {
        bookmarkRouting.requestBookmarkEditorForActiveWindowFromMenu()
    }

    func bookmarkAllTabsFromMenu() {
        bookmarkRouting.bookmarkAllTabsFromMenu()
    }

    func manageBookmarksFromMenu() {
        bookmarkRouting.manageBookmarksFromMenu()
    }

    func importBookmarksFromMenu() {
        bookmarkRouting.importBookmarksFromMenu()
    }

    func exportBookmarksFromMenu() {
        bookmarkRouting.exportBookmarksFromMenu()
    }

    func openBookmarkURLFromMenuItem(_ url: URL) {
        bookmarkRouting.openBookmarkURLFromMenuItem(url)
    }

#if DEBUG
    func printSafariExtensionAcceptanceCheckToConsole() {
        extensionDiagnostics?.printSafariExtensionAcceptanceCheckToConsole()
    }

    func printSafariExtensionNativeMessagingProbeToConsole() {
        extensionDiagnostics?.printSafariExtensionNativeMessagingProbeToConsole()
    }

    func printSafariExtensionDevDiagnosticsReportToConsole() {
        extensionDiagnostics?.printSafariExtensionDevDiagnosticsReportToConsole()
    }
#endif
}
