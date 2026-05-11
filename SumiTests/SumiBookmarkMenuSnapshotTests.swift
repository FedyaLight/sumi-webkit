import XCTest

@testable import Sumi

@MainActor
final class SumiBookmarkMenuSnapshotTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testBookmarkSnapshotProvidesManualMenuTree() throws {
        let bookmarkManager = makeBookmarkManager()
        let folder = try bookmarkManager.createFolder(title: "Docs")
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        _ = try bookmarkManager.createBookmark(
            url: url,
            title: "Reference",
            folderID: folder.id
        )

        let snapshot = bookmarkManager.snapshot(sortMode: .manual)
        let docsFolder = try XCTUnwrap(snapshot.root.children.first(where: { $0.title == "Docs" }))
        XCTAssertTrue(docsFolder.isFolder)
        XCTAssertEqual(docsFolder.children.map(\.title), ["Reference"])
        XCTAssertEqual(docsFolder.children.first?.url, url)
        XCTAssertTrue(snapshot.hasBookmarks)
    }

    func testBookmarkSnapshotEmptyStateSupportsMenuDisabledState() {
        let bookmarkManager = makeBookmarkManager()

        let snapshot = bookmarkManager.snapshot(sortMode: .manual)

        XCTAssertFalse(snapshot.hasBookmarks)
        XCTAssertTrue(snapshot.root.children.isEmpty)
    }

    private func makeBookmarkManager() -> SumiBookmarkManager {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiBookmarkMenuSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return SumiBookmarkManager(
            database: SumiBookmarkDatabase(directory: directory),
            syncFavicons: false
        )
    }
}
