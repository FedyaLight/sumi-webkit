import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiCommandsBrowserContextTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        temporaryDirectories.removeAll()
    }

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
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

        context.reopenAllWindowsFromLastSession()
        context.openHistoryURLFromMenuItem(historyURL)
        context.clearAllHistoryFromMenu()
        context.requestBookmarkEditorForActiveWindowFromMenu()
        context.bookmarkAllTabsFromMenu()
        context.manageBookmarksFromMenu()
        context.importBookmarksFromMenu()
        context.exportBookmarksFromMenu()
        context.openBookmarkURLFromMenuItem(bookmarkURL)

        XCTAssertEqual(historyRouting.events, [
            .reopenAllWindows,
            .openHistoryURL(historyURL),
            .clearAllHistory,
        ])
        XCTAssertEqual(bookmarkRouting.events, [
            .requestEditor,
            .bookmarkAllTabs,
            .manageBookmarks,
            .importBookmarks,
            .exportBookmarks,
            .openBookmarkURL(bookmarkURL),
        ])
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
            faviconService: FakeCommandFaviconService(),
            faviconImageReader: TabDependencyIsolationDefaults.faviconCapabilities.images
        )
    }

    private func makeHistoryManager() throws -> HistoryManager {
        let container = try ModelContainer(
            for: Schema([HistoryEntryEntity.self, HistoryVisitEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return HistoryManager(
            context: ModelContext(container),
            faviconCleaner: FakeCommandHistoryFaviconCleaner(),
            visitedLinkStore: FakeCommandHistoryVisitedLinkStore()
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
    func openSettingsTab(selecting pane: SettingsTabs, in windowState: BrowserWindowState?) {
        _ = (pane, windowState)
    }

    func setAsDefaultBrowser() { /* No-op. */ }
    func clearCurrentPageCookies() { /* No-op. */ }
    func createIncognitoWindow() { /* No-op. */ }
}

@MainActor
private final class FakeCommandHistoryRouting: SumiCommandHistoryRouting {
    enum Event: Equatable {
        case reopenRecentlyClosed(UUID)
        case reopenAllWindows
        case openHistoryURL(URL)
        case clearAllHistory
    }

    var canGoBackInActiveWindow = false
    var canGoForwardInActiveWindow = false
    var canRestoreAnyLastSession = false
    private(set) var events: [Event] = []

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        events.append(.reopenRecentlyClosed(item.id))
    }

    func reopenAllWindowsFromLastSession() {
        events.append(.reopenAllWindows)
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        events.append(.openHistoryURL(url))
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
