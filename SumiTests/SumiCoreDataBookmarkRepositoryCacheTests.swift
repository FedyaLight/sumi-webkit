import CoreData
import XCTest

@testable import Sumi
import SumiDomain

/// Guards the repository snapshot cache: cached trees must be dropped on
/// every mutation path (save, import, merge from another context) so reads
/// never observe stale bookmarks.
@MainActor
final class SumiCoreDataBookmarkRepositoryCacheTests: XCTestCase {
    private var directory: URL!
    private var database: SumiBookmarkDatabase!
    private var repository: SumiCoreDataBookmarkRepository!

    // The async setUp/tearDown overrides inherit the class's MainActor
    // isolation, unlike their synchronous nonisolated counterparts.
    override func setUp() async throws {
        try await super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiBookmarkRepoCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = SumiBookmarkDatabase(directory: directory)
        repository = SumiCoreDataBookmarkRepository(database: database)
    }

    override func tearDown() async throws {
        repository = nil
        database = nil
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try await super.tearDown()
    }

    func testRepeatedSnapshotsWithoutMutationsAreStable() {
        let first = repository.snapshot(sortMode: .manual)
        let second = repository.snapshot(sortMode: .manual)
        XCTAssertEqual(first, second)
    }

    func testSnapshotReflectsCreateUpdateMoveAndRemove() throws {
        _ = repository.snapshot(sortMode: .manual)

        let bookmark = try repository.createBookmark(
            url: URL(string: "https://example.com/")!,
            title: "Example",
            folderID: nil
        )
        XCTAssertNotNil(repository.snapshot(sortMode: .manual).entitiesByID[bookmark.id])

        let folder = try repository.createFolder(title: "Folder", parentID: nil)
        XCTAssertNotNil(repository.snapshot(sortMode: .manual).entitiesByID[folder.id])

        try repository.updateBookmark(
            id: bookmark.id,
            title: "Renamed",
            url: URL(string: "https://example.com/")!,
            folderID: folder.id
        )
        let afterUpdate = repository.snapshot(sortMode: .manual)
        XCTAssertEqual(afterUpdate.entitiesByID[bookmark.id]?.title, "Renamed")
        XCTAssertEqual(afterUpdate.entitiesByID[bookmark.id]?.parentID, folder.id)

        try repository.removeEntities(ids: [bookmark.id])
        XCTAssertNil(repository.snapshot(sortMode: .manual).entitiesByID[bookmark.id])
    }

    func testSnapshotReflectsImportedBookmarks() throws {
        _ = repository.snapshot(sortMode: .manual)

        let summary = try repository.importBookmarks(
            [
                SumiBookmarkImportNode(
                    name: "Imported",
                    type: .bookmark,
                    urlString: "https://imported.example/",
                    children: nil
                ),
            ],
            parentID: nil,
            acceptsURL: { _ in true },
            urlKeys: { [$0.absoluteString.lowercased()] }
        )
        XCTAssertEqual(summary.successful, 1)

        let titles = repository.snapshot(sortMode: .manual).entitiesByID.values.map(\.title)
        XCTAssertTrue(titles.contains("Imported"))
    }

    func testSnapshotReflectsMergedBackgroundContextSave() throws {
        _ = repository.snapshot(sortMode: .manual)

        let backgroundContext = database.makeContext(
            concurrencyType: .privateQueueConcurrencyType,
            name: "CacheTestBackground"
        )

        let notificationHolder = SavedNotificationHolder()
        let observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: backgroundContext,
            queue: nil
        ) { notification in
            notificationHolder.store(notification)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        backgroundContext.performAndWait {
            guard let root = BookmarkUtils.fetchRootFolder(backgroundContext) else {
                XCTFail("missing root folder in background context")
                return
            }
            _ = BookmarkEntity.makeBookmark(
                title: "FromBackground",
                url: "https://background.example/",
                parent: root,
                context: backgroundContext
            )
            do {
                try backgroundContext.save()
            } catch {
                XCTFail("background save failed: \(error)")
            }
        }

        let notification = try XCTUnwrap(notificationHolder.take())
        XCTAssertTrue(repository.mergeChanges(fromContextDidSave: notification))

        let titles = repository.snapshot(sortMode: .manual).entitiesByID.values.map(\.title)
        XCTAssertTrue(titles.contains("FromBackground"))
    }
}

/// Lock-guarded box so the did-save notification can cross from the saving
/// context's queue into the test without a non-Sendable captured var.
private final class SavedNotificationHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var notification: Notification?

    func store(_ notification: Notification) {
        lock.lock()
        self.notification = notification
        lock.unlock()
    }

    func take() -> Notification? {
        lock.lock()
        defer { lock.unlock() }
        return notification
    }
}

final class SumiURLClassifierMemoTests: XCTestCase {
    func testAlternatingInputsAreClassifiedIndependently() {
        for _ in 0..<3 {
            guard case .navigate(let url)? = SumiURLClassifier.classify("example.com") else {
                return XCTFail("expected navigate for example.com")
            }
            XCTAssertEqual(url.absoluteString, "http://example.com/")

            guard case .search(let query)? = SumiURLClassifier.classify("one two three") else {
                return XCTFail("expected search for phrase")
            }
            XCTAssertEqual(query, "one two three")
        }
    }
}
