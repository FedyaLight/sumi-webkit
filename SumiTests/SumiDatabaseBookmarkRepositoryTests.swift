import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class SumiDatabaseBookmarkRepositoryTests: XCTestCase {
    func testInitializationMigratesRootBookmarksIntoRealFavoritesWithoutMovingRootFolders() throws {
        let database = try SumiDatabase.inMemory()
        let rootBookmarkID = UUID()
        let rootFolderID = UUID()
        try database.transaction { connection in
            try connection.bookmarks.replaceAll(with: [
                BookmarkRecord(
                    id: rootBookmarkID,
                    parentID: nil,
                    name: "Existing Link",
                    urlString: "https://existing.example/",
                    kind: SumiBookmarkEntityKind.bookmark.rawValue,
                    index: 0
                ),
                BookmarkRecord(
                    id: rootFolderID,
                    parentID: nil,
                    name: "Existing Folder",
                    urlString: nil,
                    kind: SumiBookmarkEntityKind.folder.rawValue,
                    index: 1
                ),
            ])
        }

        let repository = SumiDatabaseBookmarkRepository(database: database)
        let snapshot = repository.snapshot(sortMode: .manual)
        let favorites = try XCTUnwrap(
            snapshot.entitiesByID[SumiBookmarkConstants.favoritesFolderID]
        )

        XCTAssertEqual(
            snapshot.root.children.map(\.id),
            [SumiBookmarkConstants.favoritesFolderID, rootFolderID.uuidString]
        )
        XCTAssertEqual(favorites.children.map(\.id), [rootBookmarkID.uuidString])
        XCTAssertEqual(favorites.parentID, SumiBookmarkConstants.rootFolderID)
        XCTAssertEqual(
            snapshot.entitiesByID[rootFolderID.uuidString]?.parentID,
            SumiBookmarkConstants.rootFolderID
        )
        XCTAssertEqual(
            snapshot.flattenedFolders.map(\.id),
            [SumiBookmarkConstants.favoritesFolderID, rootFolderID.uuidString]
        )
    }

    func testDefaultDestinationsKeepBookmarksInFavoritesAndFoldersAtTopLevel() throws {
        let database = try SumiDatabase.inMemory()
        let repository = SumiDatabaseBookmarkRepository(database: database)

        let bookmark = try repository.createBookmark(
            url: try XCTUnwrap(URL(string: "https://example.com/")),
            title: "Example",
            folderID: nil
        )
        let folder = try repository.createFolder(title: "Work", parentID: nil)
        let snapshot = repository.snapshot(sortMode: .manual)

        XCTAssertEqual(bookmark.folderID, SumiBookmarkConstants.favoritesFolderID)
        XCTAssertEqual(
            snapshot.root.children.map(\.id),
            [SumiBookmarkConstants.favoritesFolderID, folder.id]
        )
        XCTAssertEqual(
            snapshot.entitiesByID[SumiBookmarkConstants.favoritesFolderID]?
                .children.map(\.id),
            [bookmark.id]
        )
        XCTAssertEqual(folder.parentID, SumiBookmarkConstants.rootFolderID)
    }

    func testSnapshotsReflectMutationsAndImports() throws {
        let database = try SumiDatabase.inMemory()
        let repository = SumiDatabaseBookmarkRepository(database: database)

        let bookmark = try repository.createBookmark(
            url: try XCTUnwrap(URL(string: "https://example.com/")),
            title: "Example",
            folderID: nil
        )
        let folder = try repository.createFolder(title: "Folder", parentID: nil)
        _ = try repository.updateBookmark(
            id: bookmark.id,
            title: "Renamed",
            url: try XCTUnwrap(URL(string: "https://example.com/")),
            folderID: folder.id
        )

        var snapshot = repository.snapshot(sortMode: .manual)
        XCTAssertEqual(snapshot.entitiesByID[bookmark.id]?.title, "Renamed")
        XCTAssertEqual(snapshot.entitiesByID[bookmark.id]?.parentID, folder.id)

        let summary = try repository.importBookmarks(
            [.bookmark(name: "Imported", url: try XCTUnwrap(URL(string: "https://imported.example/")))],
            parentID: nil,
            acceptsURL: { _ in true },
            urlKeys: { [$0.absoluteString.lowercased()] }
        )
        XCTAssertEqual(summary.successful, 1)
        snapshot = repository.snapshot(sortMode: .manual)
        XCTAssertTrue(snapshot.entitiesByID.values.contains { $0.title == "Imported" })

        try repository.removeEntities(ids: [bookmark.id])
        XCTAssertNil(repository.snapshot(sortMode: .manual).entitiesByID[bookmark.id])
    }

    func testSnapshotsSortAddressesWhileKeepingFoldersFirst() throws {
        let database = try SumiDatabase.inMemory()
        let repository = SumiDatabaseBookmarkRepository(database: database)

        let folder = try repository.createFolder(title: "Folder", parentID: nil)
        let zed = try repository.createBookmark(
            url: try XCTUnwrap(URL(string: "https://zed.example/")),
            title: "First by Name",
            folderID: nil
        )
        let alpha = try repository.createBookmark(
            url: try XCTUnwrap(URL(string: "https://alpha.example/")),
            title: "Last by Name",
            folderID: nil
        )

        XCTAssertEqual(
            repository.snapshot(sortMode: .addressAscending).root.children.map(\.id),
            [SumiBookmarkConstants.favoritesFolderID, folder.id]
        )
        XCTAssertEqual(
            repository.snapshot(sortMode: .addressAscending)
                .entitiesByID[SumiBookmarkConstants.favoritesFolderID]?
                .children.map(\.id),
            [alpha.id, zed.id]
        )
        XCTAssertEqual(
            repository.snapshot(sortMode: .addressDescending)
                .entitiesByID[SumiBookmarkConstants.favoritesFolderID]?
                .children.map(\.id),
            [zed.id, alpha.id]
        )
    }
}

final class SumiURLClassifierMemoTests: XCTestCase {
    func testAlternatingInputsAreClassifiedIndependently() {
        for _ in 0..<3 {
            guard case .navigate(let url)? = SumiURLClassifier.classify("example.com") else {
                return XCTFail("expected navigate for example.com")
            }
            XCTAssertEqual(url.absoluteString, "https://example.com/")

            guard case .search(let query)? = SumiURLClassifier.classify("one two three") else {
                return XCTFail("expected search for phrase")
            }
            XCTAssertEqual(query, "one two three")
        }
    }
}
