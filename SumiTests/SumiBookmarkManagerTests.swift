import Combine
import Foundation
import XCTest

@testable import Sumi

@MainActor
final class SumiBookmarkManagerTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testCreateBookmarkIsFoundByDDGStyleURLVariants() throws {
        let manager = makeManager()
        let url = try XCTUnwrap(URL(string: "https://example.com"))

        let bookmark = try manager.createBookmark(url: url, title: "Example")

        XCTAssertEqual(manager.snapshot().root.childBookmarkCount, 1)
        XCTAssertEqual(manager.bookmark(for: url)?.id, bookmark.id)
        XCTAssertEqual(
            manager.bookmark(for: try XCTUnwrap(URL(string: "http://example.com/")))?.id,
            bookmark.id
        )
    }

    func testBookmarkFaviconSyncUsesInjectedService() async throws {
        let faviconService = FakeBookmarkFaviconService()
        let manager = SumiBookmarkManager(
            database: try SumiDatabase.inMemory(),
            faviconService: faviconService
        )
        let partition = SumiFaviconPartition(
            profileIdentifier: "bookmark-profile",
            isPrivate: false
        )
        manager.setFaviconPrefetchPartition(partition)
        let url = try XCTUnwrap(URL(string: "https://favicon.example"))

        _ = try manager.createBookmark(url: url, title: "Favicon")
        await waitForPublication(from: manager)

        XCTAssertEqual(faviconService.syncedBookmarkURLs.last, [url])
        XCTAssertEqual(faviconService.syncedBookmarkPartitions.last, partition)
    }

    func testInitialFaviconSyncCanWaitUntilFirstPaintBoundary() throws {
        let database = try SumiDatabase.inMemory()
        let url = try XCTUnwrap(URL(string: "https://deferred.example"))
        _ = try SumiBookmarkManager(
            database: database,
            syncFavicons: false
        ).createBookmark(url: url, title: "Deferred")
        let faviconService = FakeBookmarkFaviconService()
        let manager = SumiBookmarkManager(
            database: database,
            faviconService: faviconService,
            defersInitialFaviconSync: true
        )
        let partition = SumiFaviconPartition(
            profileIdentifier: "deferred-profile",
            isPrivate: false
        )

        manager.setFaviconPrefetchPartition(partition)

        XCTAssertTrue(faviconService.syncedBookmarkURLs.isEmpty)

        manager.startDeferredFaviconSync()
        manager.startDeferredFaviconSync()

        XCTAssertEqual(faviconService.syncedBookmarkURLs, [[url]])
        XCTAssertEqual(faviconService.syncedBookmarkPartitions, [partition])
    }

    func testRepeatedCreateReturnsExistingBookmark() throws {
        let manager = makeManager()
        let firstURL = try XCTUnwrap(URL(string: "https://repeat.example"))
        let variantURL = try XCTUnwrap(URL(string: "http://repeat.example/"))

        let first = try manager.createBookmark(url: firstURL, title: "First")
        let second = try manager.createBookmark(url: variantURL, title: "Second")

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(manager.snapshot().root.childBookmarkCount, 1)
        XCTAssertEqual(manager.bookmark(for: variantURL)?.title, "First")
    }

    func testUpdateAndRemoveBookmark() throws {
        let manager = makeManager()
        let originalURL = try XCTUnwrap(URL(string: "https://edit.example"))
        let updatedURL = try XCTUnwrap(URL(string: "https://edit.example/docs"))
        let bookmark = try manager.createBookmark(url: originalURL, title: "Original")

        let updated = try manager.updateBookmark(
            id: bookmark.id,
            title: "Updated",
            url: updatedURL,
            folderID: nil
        )

        XCTAssertEqual(updated.title, "Updated")
        XCTAssertNil(manager.bookmark(for: originalURL))
        XCTAssertEqual(manager.bookmark(for: updatedURL)?.id, bookmark.id)

        try manager.removeBookmark(id: bookmark.id)

        XCTAssertFalse(manager.isBookmarked(updatedURL))
        XCTAssertEqual(manager.snapshot().root.childBookmarkCount, 0)
    }

    func testDuplicateURLUpdateIsRejected() throws {
        let manager = makeManager()
        let firstURL = try XCTUnwrap(URL(string: "https://one.example"))
        let secondURL = try XCTUnwrap(URL(string: "https://two.example"))
        _ = try manager.createBookmark(url: firstURL, title: "One")
        let second = try manager.createBookmark(url: secondURL, title: "Two")

        XCTAssertThrowsError(
            try manager.updateBookmark(
                id: second.id,
                title: "Two",
                url: firstURL,
                folderID: nil
            )
        ) { error in
            XCTAssertEqual(error as? SumiBookmarkError, .duplicateURL)
        }
    }

    func testEditorStateForNewPageIsDraftUntilSaved() throws {
        let manager = makeManager()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://editor.example/path")),
            name: "Editor Page"
        )

        let addState = try manager.editorState(for: tab)

        XCTAssertEqual(addState.mode, .add)
        XCTAssertNil(addState.bookmarkID)
        XCTAssertEqual(addState.title, "Editor Page")
        XCTAssertEqual(addState.urlString, "https://editor.example/path")
        XCTAssertEqual(manager.snapshot().root.childBookmarkCount, 0)

        let savedBookmark = try manager.createBookmark(
            url: tab.url,
            title: addState.title,
            folderID: addState.folderID
        )
        let editState = try manager.editorState(for: tab)

        XCTAssertEqual(editState.mode, .edit)
        XCTAssertEqual(editState.bookmarkID, savedBookmark.id)
    }

    func testUnsupportedURLCannotBeBookmarked() throws {
        let manager = makeManager()

        XCTAssertThrowsError(
            try manager.createBookmark(
                url: URL(fileURLWithPath: "/tmp/example.html"),
                title: "File"
            )
        ) { error in
            XCTAssertEqual(error as? SumiBookmarkError, .unsupportedURL)
        }
    }

    func testTreeSnapshotSearchSortMoveAndRecursiveDelete() throws {
        let manager = makeManager()
        let folder = try manager.createFolder(title: "Docs")
        let nested = try manager.createFolder(title: "Nested", parentID: folder.id)
        let zedURL = try XCTUnwrap(URL(string: "https://zed.example"))
        let alphaURL = try XCTUnwrap(URL(string: "https://alpha.example"))
        let zed = try manager.createBookmark(url: zedURL, title: "Zed", folderID: nested.id)
        let alpha = try manager.createBookmark(url: alphaURL, title: "Alpha", folderID: folder.id)

        let snapshot = manager.snapshot()
        XCTAssertEqual(snapshot.root.childBookmarkCount, 2)
        XCTAssertEqual(snapshot.flattenedFolders.map(\.title), ["Bookmarks", "Docs", "Nested"])
        XCTAssertEqual(snapshot.entitiesByID[folder.id]?.childBookmarkCount, 2)

        XCTAssertEqual(
            manager.visibleEntities(in: folder.id, query: "", sortMode: .nameAscending).map(\.title),
            ["Nested", "Alpha"]
        )
        XCTAssertEqual(
            manager.visibleEntities(in: folder.id, query: "zed", sortMode: .manual).map(\.id),
            [zed.id]
        )

        try manager.moveEntities(ids: [alpha.id], toParentID: nil, atIndex: 0)
        XCTAssertEqual(manager.entity(id: alpha.id)?.parentID, SumiBookmarkConstants.rootFolderID)

        try manager.removeEntities(ids: [folder.id])
        XCTAssertNil(manager.entity(id: zed.id))
        XCTAssertNil(manager.entity(id: nested.id))
        XCTAssertEqual(manager.snapshot().root.childBookmarkCount, 1)
        XCTAssertEqual(manager.entity(id: alpha.id)?.id, alpha.id)
    }

    func testCannotMoveFolderIntoDescendant() throws {
        let manager = makeManager()
        let folder = try manager.createFolder(title: "Parent")
        let nested = try manager.createFolder(title: "Child", parentID: folder.id)

        XCTAssertThrowsError(
            try manager.moveEntities(ids: [folder.id], toParentID: nested.id)
        ) { error in
            XCTAssertEqual(error as? SumiBookmarkError, .cannotMoveFolderIntoDescendant)
        }
    }

    func testCreateFolderWithBookmarksBatchesReloadAndSkipsURLVariantDuplicates() throws {
        let manager = makeManager()
        let firstURL = try XCTUnwrap(URL(string: "https://batch.example"))
        let variantURL = try XCTUnwrap(URL(string: "http://batch.example/"))
        let secondURL = try XCTUnwrap(URL(string: "https://second-batch.example"))
        let revisionBeforeBatch = manager.revision

        let result = try manager.createFolderWithBookmarks(
            title: "Batch",
            bookmarks: [
                SumiBookmarkCreateRequest(url: firstURL, title: "First"),
                SumiBookmarkCreateRequest(url: variantURL, title: "Variant"),
                SumiBookmarkCreateRequest(url: secondURL, title: "Second"),
            ]
        )

        XCTAssertEqual(result.bookmarks.map(\.title), ["First", "Second"])
        XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(result.folder.title, "Batch")
        XCTAssertEqual(manager.revision, revisionBeforeBatch + 1)
        XCTAssertEqual(manager.snapshot().entitiesByID[result.folder.id]?.childBookmarkCount, 2)
        XCTAssertEqual(manager.bookmark(for: variantURL)?.title, "First")
    }

    func testIndividualCreatesCoalescePublicationAndFaviconSync() async throws {
        let faviconService = FakeBookmarkFaviconService()
        let manager = SumiBookmarkManager(
            database: try SumiDatabase.inMemory(),
            faviconService: faviconService
        )
        let urls = try [
            XCTUnwrap(URL(string: "https://batch-one.example")),
            XCTUnwrap(URL(string: "https://batch-two.example")),
            XCTUnwrap(URL(string: "https://batch-three.example")),
        ]
        let initialRevision = manager.revision
        let initialPublication = manager.publicationRevision
        let initialSyncCount = faviconService.syncedBookmarkURLs.count

        for (index, url) in urls.enumerated() {
            _ = try manager.createBookmark(
                url: url,
                title: "Bookmark \(index)"
            )
        }

        XCTAssertEqual(manager.revision, initialRevision + 3)
        XCTAssertEqual(manager.publicationRevision, initialPublication)
        XCTAssertEqual(faviconService.syncedBookmarkURLs.count, initialSyncCount)
        XCTAssertEqual(urls.compactMap(manager.bookmark(for:)).count, 3)

        await waitForPublication(from: manager)
        await Task.yield()

        XCTAssertEqual(manager.publicationRevision, initialPublication + 1)
        XCTAssertEqual(faviconService.syncedBookmarkURLs.count, initialSyncCount + 1)
        XCTAssertEqual(
            Set(faviconService.syncedBookmarkURLs.last ?? []),
            Set(urls)
        )
    }

    func testRepeatedUpdatePublishesAndSyncsOnlyFinalURL() async throws {
        let faviconService = FakeBookmarkFaviconService()
        let manager = SumiBookmarkManager(
            database: try SumiDatabase.inMemory(),
            faviconService: faviconService
        )
        let firstURL = try XCTUnwrap(URL(string: "https://update-one.example"))
        let secondURL = try XCTUnwrap(URL(string: "https://update-two.example"))
        let finalURL = try XCTUnwrap(URL(string: "https://update-final.example"))
        let bookmark = try manager.createBookmark(url: firstURL, title: "First")
        await waitForPublication(from: manager)
        let initialPublication = manager.publicationRevision
        let initialSyncCount = faviconService.syncedBookmarkURLs.count

        _ = try manager.updateBookmark(
            id: bookmark.id,
            title: "Second",
            url: secondURL,
            folderID: nil
        )
        _ = try manager.updateBookmark(
            id: bookmark.id,
            title: "Final",
            url: finalURL,
            folderID: nil
        )

        XCTAssertNil(manager.bookmark(for: firstURL))
        XCTAssertNil(manager.bookmark(for: secondURL))
        XCTAssertEqual(manager.bookmark(for: finalURL)?.title, "Final")
        XCTAssertEqual(faviconService.syncedBookmarkURLs.count, initialSyncCount)

        await waitForPublication(from: manager)

        XCTAssertEqual(manager.publicationRevision, initialPublication + 1)
        XCTAssertEqual(faviconService.syncedBookmarkURLs.count, initialSyncCount + 1)
        XCTAssertEqual(faviconService.syncedBookmarkURLs.last, [finalURL])
    }

    func testCreateThenRemoveBeforePublicationSkipsFaviconWork() async throws {
        let faviconService = FakeBookmarkFaviconService()
        let manager = SumiBookmarkManager(
            database: try SumiDatabase.inMemory(),
            faviconService: faviconService
        )
        let url = try XCTUnwrap(URL(string: "https://removed-before-publish.example"))
        let initialSyncCount = faviconService.syncedBookmarkURLs.count
        let bookmark = try manager.createBookmark(url: url, title: "Transient")
        try manager.removeBookmark(id: bookmark.id)

        XCTAssertNil(manager.bookmark(for: url))
        XCTAssertEqual(faviconService.syncedBookmarkURLs.count, initialSyncCount)

        await waitForPublication(from: manager)

        XCTAssertEqual(faviconService.syncedBookmarkURLs.count, initialSyncCount)
        XCTAssertEqual(manager.snapshot().root.childBookmarkCount, 0)
    }

    func testFolderOnlyMutationsCoalesceWithoutFaviconWork() async throws {
        let faviconService = FakeBookmarkFaviconService()
        let manager = SumiBookmarkManager(
            database: try SumiDatabase.inMemory(),
            faviconService: faviconService
        )
        let initialSyncCount = faviconService.syncedBookmarkURLs.count
        let initialPublication = manager.publicationRevision
        let folder = try manager.createFolder(title: "Draft")
        _ = try manager.updateFolder(id: folder.id, title: "Final", parentID: nil)
        _ = try manager.createFolder(title: "Nested", parentID: folder.id)

        XCTAssertEqual(manager.folders().map(\.title), ["Bookmarks", "Final", "Nested"])
        XCTAssertEqual(faviconService.syncedBookmarkURLs.count, initialSyncCount)

        await waitForPublication(from: manager)

        XCTAssertEqual(manager.publicationRevision, initialPublication + 1)
        XCTAssertEqual(faviconService.syncedBookmarkURLs.count, initialSyncCount)
    }

    func testPersistentStoreReopenPreservesBootstrapStructureIDsAndManualOrdering() throws {
        let directory = try temporaryDirectory(named: "SumiBookmarkPersistenceParity")
        let firstFolderID: String
        let nestedFolderID: String
        let rootBookmarkID: String
        let nestedBookmarkIDs: [String]

        do {
            let database = try SumiDatabase.open(at: databaseURL(in: directory))
            let manager = SumiBookmarkManager(database: database, syncFavicons: false)
            let folder = try manager.createFolder(title: "Engineering")
            let nested = try manager.createFolder(title: "Specs", parentID: folder.id)
            let firstNestedBookmark = try manager.createBookmark(
                url: try XCTUnwrap(URL(string: "https://docs.example/spec-a")),
                title: "Spec A",
                folderID: nested.id
            )
            let secondNestedBookmark = try manager.createBookmark(
                url: try XCTUnwrap(URL(string: "https://docs.example/spec-b")),
                title: "Spec B",
                folderID: nested.id
            )
            let rootBookmark = try manager.createBookmark(
                url: try XCTUnwrap(URL(string: "https://root.example")),
                title: "Root Link"
            )

            firstFolderID = folder.id
            nestedFolderID = nested.id
            rootBookmarkID = rootBookmark.id
            nestedBookmarkIDs = [firstNestedBookmark.id, secondNestedBookmark.id]

            let snapshot = manager.snapshot()
            XCTAssertEqual(snapshot.root.children.map(\.id), [firstFolderID, rootBookmarkID])
            XCTAssertEqual(snapshot.entitiesByID[nestedFolderID]?.children.map(\.id), nestedBookmarkIDs)
            XCTAssertEqual(snapshot.entitiesByID[nestedFolderID]?.parentID, firstFolderID)
        }

        let reopenedDatabase = try SumiDatabase.open(at: databaseURL(in: directory))
        let reopenedManager = SumiBookmarkManager(database: reopenedDatabase, syncFavicons: false)
        let reopenedSnapshot = reopenedManager.snapshot()

        XCTAssertEqual(reopenedSnapshot.root.id, SumiBookmarkConstants.rootFolderID)
        XCTAssertEqual(reopenedSnapshot.root.children.map(\.id), [firstFolderID, rootBookmarkID])
        XCTAssertEqual(reopenedSnapshot.entitiesByID[firstFolderID]?.title, "Engineering")
        XCTAssertEqual(reopenedSnapshot.entitiesByID[nestedFolderID]?.parentID, firstFolderID)
        XCTAssertEqual(reopenedSnapshot.entitiesByID[nestedFolderID]?.children.map(\.id), nestedBookmarkIDs)
        XCTAssertEqual(reopenedManager.bookmark(for: try XCTUnwrap(URL(string: "http://root.example/")))?.id, rootBookmarkID)
        XCTAssertEqual(reopenedSnapshot.root.childBookmarkCount, 3)
    }

    func testMoveOrderingAndDeletionSurviveStoreReopen() throws {
        let directory = try temporaryDirectory(named: "SumiBookmarkMoveOrderingParity")
        let folderAID: String
        let folderBID: String
        let firstBookmarkID: String
        let secondBookmarkID: String

        do {
            let manager = makeManager(directory: directory)
            let folderA = try manager.createFolder(title: "Folder A")
            let folderB = try manager.createFolder(title: "Folder B")
            let first = try manager.createBookmark(
                url: try XCTUnwrap(URL(string: "https://move.example/one")),
                title: "One",
                folderID: folderA.id
            )
            let second = try manager.createBookmark(
                url: try XCTUnwrap(URL(string: "https://move.example/two")),
                title: "Two",
                folderID: folderA.id
            )
            let deleted = try manager.createBookmark(
                url: try XCTUnwrap(URL(string: "https://move.example/deleted")),
                title: "Deleted",
                folderID: folderB.id
            )

            try manager.moveEntities(ids: [second.id], toParentID: folderB.id, atIndex: 0)
            try manager.moveEntities(ids: [folderA.id], toParentID: nil, atIndex: 1)
            try manager.removeBookmark(id: deleted.id)

            folderAID = folderA.id
            folderBID = folderB.id
            firstBookmarkID = first.id
            secondBookmarkID = second.id

            let snapshot = manager.snapshot()
            XCTAssertEqual(snapshot.root.children.map(\.id), [folderBID, folderAID])
            XCTAssertEqual(snapshot.entitiesByID[folderAID]?.children.map(\.id), [firstBookmarkID])
            XCTAssertEqual(snapshot.entitiesByID[folderBID]?.children.map(\.id), [secondBookmarkID])
            XCTAssertNil(snapshot.entitiesByID[deleted.id])
        }

        let reopenedManager = makeManager(directory: directory)
        let reopenedSnapshot = reopenedManager.snapshot()

        XCTAssertEqual(reopenedSnapshot.root.children.map(\.id), [folderBID, folderAID])
        XCTAssertEqual(reopenedSnapshot.entitiesByID[folderAID]?.children.map(\.id), [firstBookmarkID])
        XCTAssertEqual(reopenedSnapshot.entitiesByID[folderBID]?.children.map(\.id), [secondBookmarkID])
        XCTAssertEqual(reopenedSnapshot.entitiesByID[firstBookmarkID]?.parentID, folderAID)
        XCTAssertEqual(reopenedSnapshot.entitiesByID[secondBookmarkID]?.parentID, folderBID)
        XCTAssertNil(reopenedManager.bookmark(for: try XCTUnwrap(URL(string: "https://move.example/deleted"))))
    }

    func testImportSkipsURLVariantDuplicatesAndExportPreservesFolders() throws {
        let manager = makeManager()
        let nodes: [SumiBookmarkImportNode] = [
            .folder(
                name: "Imported",
                children: [
                    .bookmark(name: "Example", url: try XCTUnwrap(URL(string: "https://example.com"))),
                    .bookmark(name: "Example Duplicate", url: try XCTUnwrap(URL(string: "http://example.com/"))),
                    .bookmark(name: "Bad", url: try XCTUnwrap(URL(string: "ftp://example.com/file"))),
                ]
            ),
        ]

        let summary = try manager.importBookmarks(nodes)

        XCTAssertEqual(summary.successful, 2)
        XCTAssertEqual(summary.duplicates, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(manager.visibleEntities(in: nil, query: "Example", sortMode: .manual).map(\.title), ["Example"])

        let exportDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiBookmarkManagerExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        temporaryDirectories.append(exportDirectory)
        let exportURL = exportDirectory.appendingPathComponent("Bookmarks.html")
        try manager.exportBookmarksHTML(to: exportURL)
        let html = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(html.contains("<H3>Imported</H3>"))
        XCTAssertTrue(html.contains("<A HREF=\"https://example.com\">Example</A>"))
    }

    private func makeManager() -> SumiBookmarkManager {
        SumiBookmarkManager(
            database: try! SumiDatabase.inMemory(),
            syncFavicons: false
        )
    }

    private func waitForPublication(from manager: SumiBookmarkManager) async {
        let publication = expectation(description: "bookmark publication")
        var cancellable: AnyCancellable? = manager.$publicationRevision
            .dropFirst()
            .sink { _ in publication.fulfill() }
        await fulfillment(of: [publication], timeout: 1)
        cancellable?.cancel()
        cancellable = nil
    }

    private func makeManager(directory: URL) -> SumiBookmarkManager {
        SumiBookmarkManager(
            database: try! SumiDatabase.open(at: databaseURL(in: directory)),
            syncFavicons: false
        )
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func databaseURL(in directory: URL) -> URL {
        directory.appendingPathComponent("Sumi.sqlite", isDirectory: false)
    }
}

@MainActor
private final class FakeBookmarkFaviconService: BrowserFaviconServicing {
    private(set) var syncedBookmarkURLs: [[URL]] = []
    private(set) var syncedBookmarkPartitions: [SumiFaviconPartition] = []

    func partition(profile: Profile?) -> SumiFaviconPartition {
        .regular(profile?.id)
    }

    func invalidateSite(domain: String, profile: Profile?) {
        _ = (domain, profile)
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        _ = pins
    }

    func syncBookmarks(
        _ bookmarks: [SumiBookmark],
        partition: SumiFaviconPartition
    ) {
        syncedBookmarkURLs.append(bookmarks.map(\.url))
        syncedBookmarkPartitions.append(partition)
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
