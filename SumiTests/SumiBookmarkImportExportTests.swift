import SQLite3
import XCTest

import Bookmarks
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

        let nodes = try BookmarkImportSource(id: "html", title: "HTML", fileURL: fileURL, kind: .html).readBookmarks()

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

        let nodes = try BookmarkImportSource(id: "chromium", title: "Chromium", fileURL: fileURL, kind: .chromiumJSON).readBookmarks()

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

        let nodes = try BookmarkImportSource(id: "safari", title: "Safari", fileURL: fileURL, kind: .safariPlist).readBookmarks()

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.name, "Bookmarks Menu")
        XCTAssertEqual(nodes.first?.children?.first?.name, "Apple")
    }

    func testFirefoxImportReadsMinimalPlacesDatabase() throws {
        let fileURL = try temporaryFile(named: "places.sqlite")
        try createFirefoxFixture(at: fileURL)

        let nodes = try BookmarkImportSource(id: "firefox", title: "Firefox", fileURL: fileURL, kind: .firefoxSQLite).readBookmarks()

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.name, "Bookmarks Menu")
        XCTAssertEqual(nodes.first?.children?.first?.name, "Mozilla")
    }

    private func temporaryFile(named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiBookmarkImportExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent(name)
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
