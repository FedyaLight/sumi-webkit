import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class SumiDatabaseBookmarkRepositoryTests: XCTestCase {
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
