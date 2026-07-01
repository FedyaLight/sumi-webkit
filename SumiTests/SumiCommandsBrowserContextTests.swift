import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiCommandsBrowserContextTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testOpenCommandBarForActivePageUsesActivePageURLAndKeyboardPresentation() throws {
        let pageState = FakeCommandPageState()
        pageState.activePageURL = try XCTUnwrap(URL(string: "https://preview.example/session"))
        let browserActions = FakeCommandBrowserActions()
        let context = try makeContext(
            pageState: pageState,
            browserActions: browserActions
        )

        context.openCommandBarForActivePage()

        XCTAssertEqual(browserActions.focusCalls, [
            .init(
                prefill: "https://preview.example/session",
                navigateCurrentTab: true,
                presentationReason: .keyboard
            )
        ])
    }

    func testDerivedMenuStateReadsOnlyNarrowProviders() throws {
        let pageState = FakeCommandPageState()
        pageState.activePageURL = try XCTUnwrap(URL(string: "https://state.example/path"))
        pageState.hasCustomizableSpace = true
        pageState.isMuted = true
        pageState.hasAudioContent = true

        let historyRouting = FakeCommandHistoryRouting()
        historyRouting.canGoBackInActiveWindow = true
        historyRouting.canGoForwardInActiveWindow = true
        historyRouting.canRestoreAnyLastSession = true

        let bookmarkRouting = FakeCommandBookmarkRouting()
        bookmarkRouting.canBookmarkAllTabs = true

        let context = try makeContext(
            pageState: pageState,
            historyRouting: historyRouting,
            bookmarkRouting: bookmarkRouting
        )

        XCTAssertEqual(context.activePageHost, "state.example")
        XCTAssertTrue(context.canCustomizeSpaceGradient)
        XCTAssertTrue(context.canGoBackInActiveWindow)
        XCTAssertTrue(context.canGoForwardInActiveWindow)
        XCTAssertTrue(context.canRestoreAnyLastSession)
        XCTAssertTrue(context.canBookmarkAllTabsInActiveWindow)
        XCTAssertTrue(context.currentTabIsMuted)
        XCTAssertTrue(context.currentTabHasAudioContent)
    }

    func testHistoryAndBookmarkCommandsRouteToDedicatedRoles() throws {
        let historyRouting = FakeCommandHistoryRouting()
        let bookmarkRouting = FakeCommandBookmarkRouting()
        let context = try makeContext(
            historyRouting: historyRouting,
            bookmarkRouting: bookmarkRouting
        )
        let historyURL = try XCTUnwrap(URL(string: "https://history.example/"))
        let bookmarkURL = try XCTUnwrap(URL(string: "https://bookmark.example/"))

        context.goBackInActiveWindow()
        context.goForwardInActiveWindow()
        context.reopenMostRecentClosedItem()
        context.reopenAllWindowsFromLastSession()
        context.openHistoryURLFromMenuItem(historyURL)
        context.showHistory()
        context.clearAllHistoryFromMenu()
        context.requestBookmarkEditorForActiveWindowFromMenu()
        context.bookmarkAllTabsFromMenu()
        context.manageBookmarksFromMenu()
        context.importBookmarksFromMenu()
        context.exportBookmarksFromMenu()
        context.openBookmarkURLFromMenuItem(bookmarkURL)

        XCTAssertEqual(historyRouting.events, [
            .goBack,
            .goForward,
            .reopenMostRecent,
            .reopenAllWindows,
            .openHistoryURL(historyURL),
            .showHistory,
            .clearAllHistory
        ])
        XCTAssertEqual(bookmarkRouting.events, [
            .requestEditor,
            .bookmarkAllTabs,
            .manageBookmarks,
            .importBookmarks,
            .exportBookmarks,
            .openBookmarkURL(bookmarkURL)
        ])
    }

    func testCloseCommandsForwardExplicitWindowTargets() throws {
        let browserActions = FakeCommandBrowserActions()
        let context = try makeContext(browserActions: browserActions)
        let tabWindow = BrowserWindowState()
        let closeWindow = BrowserWindowState()

        context.closeCurrentTab(in: tabWindow)
        context.closeWindow(closeWindow)

        XCTAssertEqual(browserActions.closedTabWindowIds, [tabWindow.id])
        XCTAssertEqual(browserActions.closedWindowIds, [closeWindow.id])
    }

    private func makeContext(
        pageState: FakeCommandPageState = FakeCommandPageState(),
        browserActions: FakeCommandBrowserActions = FakeCommandBrowserActions(),
        historyRouting: FakeCommandHistoryRouting = FakeCommandHistoryRouting(),
        bookmarkRouting: FakeCommandBookmarkRouting = FakeCommandBookmarkRouting()
    ) throws -> SumiCommandsBrowserContext {
        SumiCommandsBrowserContext(
            pageState: pageState,
            browserActions: browserActions,
            historyRouting: historyRouting,
            bookmarkRouting: bookmarkRouting,
            recentlyClosedManager: RecentlyClosedManager(),
            historyManager: try makeHistoryManager(),
            bookmarkManager: makeBookmarkManager(),
            faviconService: FakeCommandFaviconService()
        )
    }

    private func makeHistoryManager() throws -> HistoryManager {
        let container = try ModelContainer(
            for: Schema([HistoryEntryEntity.self, HistoryVisitEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return HistoryManager(
            context: ModelContext(container),
            dependencies: HistoryManager.Dependencies(
                faviconCleaner: FakeCommandHistoryFaviconCleaner(),
                visitedLinkStore: FakeCommandHistoryVisitedLinkStore()
            )
        )
    }

    private func makeBookmarkManager() -> SumiBookmarkManager {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiCommandsBrowserContextTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return SumiBookmarkManager(
            database: SumiBookmarkDatabase(directory: directory),
            syncFavicons: false
        )
    }
}

@MainActor
private final class FakeCommandPageState: SumiCommandPageStateProviding {
    var currentProfile: Profile?
    var activePageTab: Tab?
    var activePageURL: URL?
    var isMuted = false
    var hasAudioContent = false
    var hasCustomizableSpace = false

    func activePageTabForActiveWindow() -> Tab? {
        activePageTab
    }

    func activePageURLForActiveWindow() -> URL? {
        activePageURL
    }

    func currentTabIsMuted() -> Bool {
        isMuted
    }

    func currentTabHasAudioContent() -> Bool {
        hasAudioContent
    }

    func hasCustomizableSpaceForCommands() -> Bool {
        hasCustomizableSpace
    }
}

@MainActor
private final class FakeCommandBrowserActions: SumiCommandBrowserActionRouting {
    struct FocusCall: Equatable {
        let prefill: String
        let navigateCurrentTab: Bool
        let presentationReason: FloatingBarPresentationReason
    }

    private(set) var focusCalls: [FocusCall] = []
    private(set) var closedTabWindowIds: [UUID] = []
    private(set) var closedWindowIds: [UUID] = []

    func openSettingsTab(selecting pane: SettingsTabs, in windowState: BrowserWindowState?) {
        _ = (pane, windowState)
    }

    func setAsDefaultBrowser() {}
    func clearCurrentPageCookies() {}
    func showGradientEditor() {}
    func showQuitDialog() {}
    func closeCurrentTab() {}
    func closeCurrentTab(in windowState: BrowserWindowState) {
        closedTabWindowIds.append(windowState.id)
    }
    func closeActiveWindow() {}
    func closeWindow(_ windowState: BrowserWindowState) {
        closedWindowIds.append(windowState.id)
    }
    func undoCloseTab() {}
    func openNewTabSurfaceInActiveWindow() {}
    func createNewWindow() {}
    func createIncognitoWindow() {}

    func focusFloatingBarForActiveWindow(
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason
    ) {
        focusCalls.append(
            FocusCall(
                prefill: prefill,
                navigateCurrentTab: navigateCurrentTab,
                presentationReason: presentationReason
            )
        )
    }

    func copyCurrentURL() {}
    func toggleSidebar() {}
    func showFindBar() {}
    func refreshCurrentTabInActiveWindow() {}
    func zoomInCurrentTab() {}
    func zoomOutCurrentTab() {}
    func resetZoomCurrentTab() {}
    func hardReloadCurrentPage() {}
    func openWebInspector() {}
    func toggleMuteCurrentTabInActiveWindow() {}
}

@MainActor
private final class FakeCommandHistoryRouting: SumiCommandHistoryRouting {
    enum Event: Equatable {
        case goBack
        case goForward
        case reopenMostRecent
        case reopenRecentlyClosed(UUID)
        case reopenAllWindows
        case openHistoryURL(URL)
        case showHistory
        case clearAllHistory
    }

    var canGoBackInActiveWindow = false
    var canGoForwardInActiveWindow = false
    var canRestoreAnyLastSession = false
    private(set) var events: [Event] = []

    func goBackInActiveWindow() {
        events.append(.goBack)
    }

    func goForwardInActiveWindow() {
        events.append(.goForward)
    }

    func reopenMostRecentClosedItem() {
        events.append(.reopenMostRecent)
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        events.append(.reopenRecentlyClosed(item.id))
    }

    func reopenAllWindowsFromLastSession() {
        events.append(.reopenAllWindows)
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        events.append(.openHistoryURL(url))
    }

    func showHistory() {
        events.append(.showHistory)
    }

    func clearAllHistoryFromMenu() {
        events.append(.clearAllHistory)
    }
}

@MainActor
private final class FakeCommandBookmarkRouting: SumiCommandBookmarkRouting {
    enum Event: Equatable {
        case requestEditor
        case bookmarkAllTabs
        case manageBookmarks
        case importBookmarks
        case exportBookmarks
        case openBookmarkURL(URL)
    }

    var canBookmarkAllTabs = false
    private(set) var events: [Event] = []

    func canBookmarkAllTabsInActiveWindow() -> Bool {
        canBookmarkAllTabs
    }

    func requestBookmarkEditorForActiveWindowFromMenu() {
        events.append(.requestEditor)
    }

    func bookmarkAllTabsFromMenu() {
        events.append(.bookmarkAllTabs)
    }

    func manageBookmarksFromMenu() {
        events.append(.manageBookmarks)
    }

    func importBookmarksFromMenu() {
        events.append(.importBookmarks)
    }

    func exportBookmarksFromMenu() {
        events.append(.exportBookmarks)
    }

    func openBookmarkURLFromMenuItem(_ url: URL) {
        events.append(.openBookmarkURL(url))
    }
}

@MainActor
private final class FakeCommandFaviconService: BrowserFaviconServicing {
    func partition(profile: Profile?) -> SumiFaviconPartition {
        .regular(profile?.id)
    }

    func invalidateSite(domain: String, profile: Profile?) {
        _ = (domain, profile)
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        _ = pins
    }

    func syncBookmarks(_ bookmarks: [SumiBookmark], partition: SumiFaviconPartition) {
        _ = (bookmarks, partition)
    }

    func clearFaviconPartition(for profile: Profile) {
        _ = profile
    }

#if DEBUG
    func drainRuntimeTasksForTests(cancel: Bool) async {
        _ = cancel
    }
#endif
}

@MainActor
private final class FakeCommandHistoryFaviconCleaner: HistoryFaviconCleaning {
    func burnAfterHistoryClear(savedLogins: Set<String>) async {
        _ = savedLogins
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>
    ) async {
        _ = (domains, remainingHistoryHosts, savedLogins)
    }
}

@MainActor
private final class FakeCommandHistoryVisitedLinkStore: HistoryVisitedLinkStoring {
    func preloadVisitedLinks(_ urls: [URL], for profileId: UUID) {
        _ = (urls, profileId)
    }

    func replaceVisitedLinks(_ urls: [URL], for profileId: UUID) {
        _ = (urls, profileId)
    }
}
