import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiBookmarksSurfaceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testBookmarksSurfaceURLAndTabClassification() {
        let url = SumiSurface.bookmarksSurfaceURL(selecting: "folder-id")
        let tab = Tab(url: url, name: "Bookmarks")

        XCTAssertTrue(SumiSurface.isBookmarksSurfaceURL(url))
        XCTAssertEqual(SumiSurface.bookmarksSelectedFolderID(from: url), "folder-id")
        XCTAssertTrue(tab.representsSumiBookmarksSurface)
        XCTAssertTrue(tab.representsSumiNativeSurface)
        XCTAssertTrue(tab.representsSumiInternalSurface)
        XCTAssertFalse(tab.requiresPrimaryWebView)
    }

    func testOpenBookmarksTabCreatesAndReusesManagerTabInCurrentSpace() throws {
        let harness = try makeHarness()

        harness.browserManager.openBookmarksTab(selecting: "first", in: harness.windowState)
        let firstBookmarksTab = try XCTUnwrap(
            harness.browserManager.tabManager.tabs(in: harness.space).first(where: \.representsSumiBookmarksSurface)
        )
        XCTAssertEqual(SumiSurface.bookmarksSelectedFolderID(from: firstBookmarksTab.url), "first")

        harness.browserManager.openBookmarksTab(selecting: "second", in: harness.windowState)

        let bookmarksTabs = harness.browserManager.tabManager.tabs(in: harness.space)
            .filter(\.representsSumiBookmarksSurface)
        XCTAssertEqual(bookmarksTabs.count, 1)
        XCTAssertEqual(bookmarksTabs.first?.id, firstBookmarksTab.id)
        XCTAssertEqual(SumiSurface.bookmarksSelectedFolderID(from: bookmarksTabs[0].url), "second")
    }

    func testBookmarkTabsCreatesFolderSkipsDuplicatesAndUnsupportedTabs() throws {
        let harness = try makeHarness()
        let firstURL = try XCTUnwrap(URL(string: "https://first.example"))
        let secondURL = try XCTUnwrap(URL(string: "https://second.example"))
        _ = try harness.browserManager.bookmarkManager.createBookmark(url: firstURL, title: "Existing")

        let duplicate = Tab(url: firstURL, name: "Duplicate", browserManager: harness.browserManager)
        let fresh = Tab(url: secondURL, name: "Second", browserManager: harness.browserManager)
        let unsupported = Tab(url: SumiSurface.emptyTabURL, name: "Empty", browserManager: harness.browserManager)

        let result = try harness.browserManager.bookmarkTabs(
            [duplicate, fresh, unsupported],
            folderTitle: "Saved Tabs",
            parentID: nil
        )

        XCTAssertEqual(result.created, 1)
        XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.folderTitle, "Saved Tabs")
        XCTAssertEqual(harness.browserManager.bookmarkManager.bookmark(for: secondURL)?.title, "Second")
        XCTAssertEqual(harness.browserManager.bookmarkManager.bookmarks().count, 2)
    }

    private func makeHarness() throws -> (
        browserManager: BrowserManager,
        windowRegistry: WindowRegistry,
        windowState: BrowserWindowState,
        space: Space
    ) {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.modelContext = context
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.historyManager = HistoryManager(context: context, profileId: profile.id)
        browserManager.recentlyClosedManager = RecentlyClosedManager()
        browserManager.lastSessionWindowsStore = LastSessionWindowsStore()
        browserManager.bookmarkManager = makeBookmarkManager()
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (browserManager, windowRegistry, windowState, space)
    }

    private func makeBookmarkManager() -> SumiBookmarkManager {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiBookmarksSurfaceTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return SumiBookmarkManager(
            database: SumiBookmarkDatabase(directory: directory),
            syncFavicons: false
        )
    }
}
