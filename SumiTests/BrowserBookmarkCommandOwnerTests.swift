import XCTest

@testable import Sumi

@MainActor
final class BrowserBookmarkCommandOwnerTests: XCTestCase {
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

    func testRequestBookmarkEditorSetsRequestOnlyForActiveBookmarkablePage() throws {
        let harness = makeHarness()
        let presenter = FakeBookmarkCommandPresenter()
        let owner = harness.makeOwner(presenter: presenter)
        let windowState = BrowserWindowState()
        let bookmarkableTab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            name: "Example"
        )

        harness.activeWindow = windowState
        harness.activeTabsByWindowID[windowState.id] = bookmarkableTab

        owner.requestBookmarkEditorForActiveWindowFromMenu()

        XCTAssertEqual(harness.bookmarkEditorPresentationRequest?.windowID, windowState.id)
        XCTAssertEqual(harness.bookmarkEditorPresentationRequest?.tabID, bookmarkableTab.id)

        let existingRequest = try XCTUnwrap(harness.bookmarkEditorPresentationRequest)
        harness.activeTabsByWindowID[windowState.id] = Tab(
            url: SumiSurface.emptyTabURL,
            name: "Empty"
        )

        owner.requestBookmarkEditorForActiveWindowFromMenu()

        XCTAssertEqual(harness.bookmarkEditorPresentationRequest, existingRequest)
    }

    func testOpenBookmarkURLFromMenuUsesHistoryRoutingForActiveWindowOtherwiseNewWindow() throws {
        let harness = makeHarness()
        let presenter = FakeBookmarkCommandPresenter()
        let owner = harness.makeOwner(presenter: presenter)
        let windowState = BrowserWindowState()
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))

        harness.activeWindow = windowState

        owner.openBookmarkURLFromMenuItem(url)

        XCTAssertEqual(harness.openedHistoryURLs.count, 1)
        XCTAssertEqual(harness.openedHistoryURLs[0].url, url)
        XCTAssertEqual(harness.openedHistoryURLs[0].windowID, windowState.id)
        guard case .currentTab = harness.openedHistoryURLs[0].mode else {
            XCTFail("Expected current-tab history routing")
            return
        }
        XCTAssertTrue(harness.openedHistoryURLGroupsInNewWindow.isEmpty)

        harness.activeWindow = nil

        owner.openBookmarkURLFromMenuItem(url)

        XCTAssertEqual(harness.openedHistoryURLGroupsInNewWindow, [[url]])
    }

    func testBookmarkAllTabsScopesToCurrentSpaceAndIgnoresIncognitoWindows() throws {
        let harness = makeHarness()
        let presenter = FakeBookmarkCommandPresenter()
        let owner = harness.makeOwner(presenter: presenter)
        let profileID = UUID()
        let space = Space(name: "Primary", profileId: profileID)
        let windowState = BrowserWindowState()
        let firstURL = try XCTUnwrap(URL(string: "https://first.example"))
        let outsideURL = try XCTUnwrap(URL(string: "https://outside.example"))
        let firstTab = Tab(url: firstURL, name: "First")
        let unsupportedTab = Tab(url: SumiSurface.emptyTabURL, name: "Empty")
        let outsideTab = Tab(url: outsideURL, name: "Outside")

        windowState.currentSpaceId = space.id
        harness.activeWindow = windowState
        harness.spacesByID[space.id] = space
        harness.tabsBySpaceID[space.id] = [firstTab, unsupportedTab]
        harness.allTabsValue = [outsideTab]
        presenter.bookmarkAllTabsPrompt = BrowserBookmarkAllTabsPrompt(
            folderTitle: "Saved Tabs",
            parentID: nil
        )

        XCTAssertTrue(owner.canBookmarkAllTabsInActiveWindow())

        owner.bookmarkAllTabsFromMenu()

        XCTAssertEqual(harness.bookmarkManager.bookmark(for: firstURL)?.title, "First")
        XCTAssertNil(harness.bookmarkManager.bookmark(for: outsideURL))
        XCTAssertEqual(presenter.alerts.last?.title, "Tabs Bookmarked")
        XCTAssertEqual(
            presenter.alerts.last?.message,
            "1 added to “Saved Tabs”. 0 duplicates skipped. 1 unsupported tabs ignored."
        )

        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        incognitoWindow.currentSpaceId = space.id
        harness.activeWindow = incognitoWindow

        XCTAssertFalse(owner.canBookmarkAllTabsInActiveWindow())
    }

    func testImportUnreadableSafariSourceUsesManualReplacementFile() throws {
        let harness = makeHarness()
        let presenter = FakeBookmarkCommandPresenter()
        let owner = harness.makeOwner(presenter: presenter)
        let importedURL = try XCTUnwrap(URL(string: "https://manual.example"))
        let source = SumiBookmarkImportSource(
            id: "safari",
            title: "Safari",
            fileURL: URL(fileURLWithPath: "/unreadable/Bookmarks.plist"),
            kind: .safariPlist
        )
        let replacementURL = URL(fileURLWithPath: "/manual/Bookmarks.plist")

        harness.detectedImportSourcesValue = [source]
        harness.readBookmarksHandler = { requestedSource in
            if requestedSource.id == "safari" {
                throw TestImportError.unreadable
            }
            XCTAssertEqual(requestedSource.id, "safari-manual")
            XCTAssertEqual(requestedSource.fileURL, replacementURL)
            return [
                .bookmark(name: "Manual", url: importedURL),
            ]
        }
        presenter.importSelection = .source(source)
        presenter.unreadableSafariReplacementURL = replacementURL

        owner.importBookmarksFromMenu()

        XCTAssertEqual(presenter.promptedImportSources, [[source]])
        XCTAssertEqual(presenter.unreadableSafariPrompts, [source])
        XCTAssertEqual(harness.bookmarkManager.bookmark(for: importedURL)?.title, "Manual")
        XCTAssertEqual(presenter.alerts.last?.title, "Bookmarks Imported")
    }

    private func makeHarness() -> BrowserBookmarkCommandOwnerHarness {
        BrowserBookmarkCommandOwnerHarness(bookmarkManager: makeBookmarkManager())
    }

    private func makeBookmarkManager() -> SumiBookmarkManager {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("BrowserBookmarkCommandOwnerTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return SumiBookmarkManager(
            database: SumiBookmarkDatabase(directory: directory),
            syncFavicons: false
        )
    }
}

@MainActor
private final class BrowserBookmarkCommandOwnerHarness {
    struct OpenedHistoryURL {
        var url: URL
        var windowID: UUID
        var mode: HistoryOpenMode
    }

    let bookmarkManager: SumiBookmarkManager
    var activeWindow: BrowserWindowState?
    var activeTabsByWindowID: [UUID: Tab] = [:]
    var bookmarkEditorPresentationRequest: SumiBookmarkEditorPresentationRequest?
    var openedHistoryURLs: [OpenedHistoryURL] = []
    var openedHistoryURLGroupsInNewWindow: [[URL]] = []
    var windowIdsValue: [UUID] = []
    var createNewWindowCallCount = 0
    var nextRegisteredWindow: BrowserWindowState?
    var awaitedExistingWindowIDs: [Set<UUID>] = []
    var spacesByID: [UUID: Space] = [:]
    var tabsBySpaceID: [UUID: [Tab]] = [:]
    var allTabsValue: [Tab] = []
    var detectedImportSourcesValue: [SumiBookmarkImportSource] = []
    var dateValue = Date(timeIntervalSince1970: 1_704_067_200)
    var readBookmarksHandler: (SumiBookmarkImportSource) throws -> [SumiBookmarkImportNode] = { source in
        try source.readBookmarks()
    }

    init(bookmarkManager: SumiBookmarkManager) {
        self.bookmarkManager = bookmarkManager
    }

    func makeOwner(presenter: FakeBookmarkCommandPresenter) -> BrowserBookmarkCommandOwner {
        BrowserBookmarkCommandOwner(
            dependencies: BrowserBookmarkCommandOwner.Dependencies(
                activeWindow: { [weak self] in
                    self?.activeWindow
                },
                activePageTab: { [weak self] windowState in
                    self?.activeTabsByWindowID[windowState.id]
                },
                bookmarkManager: { [weak self] in
                    self?.bookmarkManager
                },
                bookmarkEditorPresentationRequest: { [weak self] in
                    self?.bookmarkEditorPresentationRequest
                },
                setBookmarkEditorPresentationRequest: { [weak self] request in
                    self?.bookmarkEditorPresentationRequest = request
                },
                openNativeBrowserSurface: { _, _, _, _ in /* No-op. */ },
                openHistoryURL: { [weak self] url, windowState, mode in
                    self?.openedHistoryURLs.append(
                        OpenedHistoryURL(
                            url: url,
                            windowID: windowState.id,
                            mode: mode
                        )
                    )
                },
                openHistoryURLsInNewWindow: { [weak self] urls in
                    self?.openedHistoryURLGroupsInNewWindow.append(urls)
                },
                windowIds: { [weak self] in
                    self?.windowIdsValue ?? []
                },
                createNewWindow: { [weak self] in
                    self?.createNewWindowCallCount += 1
                },
                awaitNextRegisteredWindow: { [weak self] existingWindowIDs in
                    self?.awaitedExistingWindowIDs.append(existingWindowIDs)
                    return self?.nextRegisteredWindow
                },
                space: { [weak self] spaceID in
                    guard let spaceID else { return nil }
                    return self?.spacesByID[spaceID]
                },
                tabsInSpace: { [weak self] space in
                    self?.tabsBySpaceID[space.id] ?? []
                },
                allTabs: { [weak self] in
                    self?.allTabsValue ?? []
                },
                detectedImportSources: { [weak self] in
                    self?.detectedImportSourcesValue ?? []
                },
                readBookmarks: { [weak self] source in
                    try self?.readBookmarksHandler(source) ?? []
                },
                date: { [weak self] in
                    self?.dateValue ?? Date(timeIntervalSince1970: 0)
                }
            ),
            presenter: presenter
        )
    }
}

@MainActor
private final class FakeBookmarkCommandPresenter: BrowserBookmarkCommandPresenting {
    var bookmarkAllTabsPrompt: BrowserBookmarkAllTabsPrompt?
    var importSelection: BrowserBookmarkImportSelection?
    var htmlImportURL: URL?
    var unreadableSafariReplacementURL: URL?
    var exportDestinationURL: URL?
    var promptedImportSources: [[SumiBookmarkImportSource]] = []
    var unreadableSafariPrompts: [SumiBookmarkImportSource] = []
    var alerts: [(title: String, message: String)] = []

    func promptBookmarkAllTabs(
        defaultTitle _: String,
        folders _: [SumiBookmarkFolder]
    ) -> BrowserBookmarkAllTabsPrompt? {
        bookmarkAllTabsPrompt
    }

    func promptImportSource(
        detectedSources: [SumiBookmarkImportSource]
    ) -> BrowserBookmarkImportSelection? {
        promptedImportSources.append(detectedSources)
        return importSelection
    }

    func promptHTMLImportFile() -> URL? {
        htmlImportURL
    }

    func promptUnreadableSafariBookmarksReplacement(
        source: SumiBookmarkImportSource,
        originalError _: Error
    ) -> URL? {
        unreadableSafariPrompts.append(source)
        return unreadableSafariReplacementURL
    }

    func promptExportDestination(defaultFileName _: String) -> URL? {
        exportDestinationURL
    }

    func showBookmarkResultAlert(title: String, message: String) {
        alerts.append((title, message))
    }
}

private enum TestImportError: Error {
    case unreadable
}
