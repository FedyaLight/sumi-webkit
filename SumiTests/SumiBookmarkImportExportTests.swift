import SQLite3
import XCTest

@testable import Sumi

final class SumiBookmarkImportExportTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testHTMLImportReadsNestedFoldersAndBookmarks() throws {
        let fileURL = try temporaryFile(named: "bookmarks.html")
        try """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Docs</H3>
            <DL><p>
                <DT><A HREF="https://example.com/docs">Docs Home</A>
            </DL><p>
        </DL><p>
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let nodes = try SumiBookmarkImportSource(id: "html", title: "HTML", fileURL: fileURL, kind: .html).readBookmarks()

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.name, "Docs")
        XCTAssertEqual(nodes.first?.children?.first?.name, "Docs Home")
    }

    func testChromiumImportReadsBookmarkBarAsOrdinaryFolder() throws {
        let fileURL = try temporaryFile(named: "Bookmarks")
        try """
        {
          "roots": {
            "bookmark_bar": {
              "type": "folder",
              "name": "Bookmarks Bar",
              "children": [
                { "type": "url", "name": "Toolbar", "url": "https://toolbar.example" }
              ]
            },
            "other": {
              "type": "folder",
              "name": "Other",
              "children": [
                { "type": "url", "name": "Other", "url": "https://other.example" }
              ]
            },
            "synced": {
              "type": "folder",
              "name": "Mobile",
              "children": []
            }
          }
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let nodes = try SumiBookmarkImportSource(
            id: "chromium",
            title: "Chromium",
            fileURL: fileURL,
            kind: .chromiumJSON
        ).readBookmarks()

        XCTAssertEqual(nodes.map(\.name), ["Bookmarks Bar", "Other"])
        XCTAssertEqual(nodes.first?.children?.first?.name, "Toolbar")
    }

    func testSafariImportSkipsReadingList() throws {
        let fileURL = try temporaryFile(named: "Bookmarks.plist")
        let plist: [String: Any] = [
            "Children": [
                [
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "BookmarksMenu",
                    "Children": [
                        [
                            "WebBookmarkType": "WebBookmarkTypeLeaf",
                            "URLString": "https://apple.example",
                            "URIDictionary": ["title": "Apple"],
                        ],
                    ],
                ],
                [
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "com.apple.ReadingList",
                    "Children": [
                        [
                            "WebBookmarkType": "WebBookmarkTypeLeaf",
                            "URLString": "https://reading.example",
                            "URIDictionary": ["title": "Reading"],
                        ],
                    ],
                ],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: fileURL)

        let nodes = try SumiBookmarkImportSource(
            id: "safari",
            title: "Safari",
            fileURL: fileURL,
            kind: .safariPlist
        ).readBookmarks()

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.name, "Bookmarks Menu")
        XCTAssertEqual(nodes.first?.children?.first?.name, "Apple")
    }

    func testFirefoxImportReadsMinimalPlacesDatabase() throws {
        let fileURL = try temporaryFile(named: "places.sqlite")
        try createFirefoxFixture(at: fileURL)

        let nodes = try SumiBookmarkImportSource(
            id: "firefox",
            title: "Firefox",
            fileURL: fileURL,
            kind: .firefoxSQLite
        ).readBookmarks()

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.name, "Bookmarks Menu")
        XCTAssertEqual(nodes.first?.children?.first?.name, "Mozilla")
    }

    @MainActor
    func testHTMLImportExportRoundTripPreservesSummaryAndNestedStructure() throws {
        let sourceURL = try temporaryFile(named: "source-bookmarks.html")
        try """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Engineering</H3>
            <DL><p>
                <DT><A HREF="https://docs.example/start">Docs Home</A>
                <DT><H3>Specs</H3>
                <DL><p>
                    <DT><A HREF="https://docs.example/spec-a">Spec A</A>
                </DL><p>
            </DL><p>
        </DL><p>
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        let importedNodes = try SumiBookmarkImportSource(
            id: "source-html",
            title: "Source HTML",
            fileURL: sourceURL,
            kind: .html
        ).readBookmarks()
        let firstManager = try makeBookmarkManager()

        let firstSummary = try firstManager.importBookmarks(importedNodes)

        XCTAssertEqual(firstSummary, SumiBookmarksImportSummary(successful: 4, duplicates: 0, failed: 0))
        XCTAssertEqual(bookmarkOutline(in: firstManager), [
            "folder:Engineering",
            "  bookmark:Docs Home|https://docs.example/start",
            "  folder:Specs",
            "    bookmark:Spec A|https://docs.example/spec-a",
        ])

        let exportURL = try temporaryFile(named: "exported-bookmarks.html")
        try firstManager.exportBookmarksHTML(to: exportURL)
        let reimportedNodes = try SumiBookmarkImportSource(
            id: "round-trip-html",
            title: "Round Trip HTML",
            fileURL: exportURL,
            kind: .html
        ).readBookmarks()
        let secondManager = try makeBookmarkManager()

        let secondSummary = try secondManager.importBookmarks(reimportedNodes)

        XCTAssertEqual(secondSummary, firstSummary)
        XCTAssertEqual(bookmarkOutline(in: secondManager), bookmarkOutline(in: firstManager))
    }

    private func temporaryFile(named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiBookmarkImportExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent(name)
    }

    @MainActor
    private func makeBookmarkManager() throws -> SumiBookmarkManager {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiBookmarkImportExportManager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return SumiBookmarkManager(
            database: SumiBookmarkDatabase(directory: directory),
            syncFavicons: false
        )
    }

    @MainActor
    private func bookmarkOutline(in manager: SumiBookmarkManager) -> [String] {
        func lines(for entity: SumiBookmarkEntity, depth: Int) -> [String] {
            entity.children.flatMap { child -> [String] in
                let prefix = String(repeating: "  ", count: depth)
                if child.isFolder {
                    return ["\(prefix)folder:\(child.title)"] + lines(for: child, depth: depth + 1)
                }
                return ["\(prefix)bookmark:\(child.title)|\(child.displayURL)"]
            }
        }

        return lines(for: manager.snapshot().root, depth: 0)
    }

    private func createFirefoxFixture(at fileURL: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fileURL.path, &database), SQLITE_OK)
        guard let database else {
            XCTFail("Could not open sqlite fixture")
            return
        }
        defer { sqlite3_close(database) }

        try execute(
            """
            CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT);
            CREATE TABLE moz_bookmarks (
                id INTEGER PRIMARY KEY,
                type INTEGER,
                fk INTEGER,
                parent INTEGER,
                position INTEGER,
                title TEXT,
                guid TEXT
            );
            INSERT INTO moz_places (id, url, title) VALUES (10, 'https://mozilla.example', 'Mozilla');
            INSERT INTO moz_bookmarks (id, type, fk, parent, position, title, guid)
                VALUES (2, 2, NULL, 1, 0, 'Bookmarks Menu', 'menu________');
            INSERT INTO moz_bookmarks (id, type, fk, parent, position, title, guid)
                VALUES (3, 1, 10, 2, 0, 'Mozilla', 'bookmark____');
            """,
            database: database
        )
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown sqlite error"
            sqlite3_free(errorMessage)
            throw NSError(domain: "SQLiteFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
