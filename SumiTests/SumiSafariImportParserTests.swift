import XCTest

@testable import Sumi

final class SumiSafariImportParserTests: XCTestCase {
    private var safari: URL!

    override func setUpWithError() throws {
        safari = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiSafariImportParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: safari)
    }

    func testImportsBookmarksAndLastSessionTabs() throws {
        try writeBookmarks()
        try writePlist(
            [
                "SessionWindows": [[
                    "TabStates": [
                        ["TabURL": "https://one.example", "TabTitle": "One"],
                        ["TabURL": "https://two.example", "TabTitle": "Two"],
                    ]
                ]]
            ],
            named: "LastSession.plist"
        )

        let result = try parse()

        XCTAssertEqual(result.data.regularTabs.map(\.urlString), ["https://one.example", "https://two.example"])
        XCTAssertEqual(result.data.regularTabs.map(\.title), ["One", "Two"])
        XCTAssertEqual(result.data.bookmarks.first?.totalBookmarkCount, 1)
        XCTAssertEqual(result.data.spaces.map(\.name), ["Safari"])
    }

    /// `LastSession.plist` has no published schema and has changed shape across
    /// releases, so tab records are found by search rather than a fixed path.
    func testFindsTabsUnderAnUnfamiliarStructure() throws {
        try writeBookmarks()
        try writePlist(
            ["Something": ["Nested": ["Deeper": [["URL": "https://found.example", "Title": "Found"]]]]],
            named: "LastSession.plist"
        )

        XCTAssertEqual(try parse().data.regularTabs.map(\.urlString), ["https://found.example"])
    }

    func testIgnoresNonWebEntriesAndDuplicates() throws {
        try writeBookmarks()
        try writePlist(
            [
                "SessionWindows": [[
                    "TabStates": [
                        ["TabURL": "https://kept.example", "TabTitle": "Kept"],
                        ["TabURL": "https://kept.example", "TabTitle": "Duplicate"],
                        ["TabURL": "file:///etc/passwd", "TabTitle": "Local"],
                        ["TabURL": "about:blank"],
                    ]
                ]]
            ],
            named: "LastSession.plist"
        )

        XCTAssertEqual(try parse().data.regularTabs.map(\.urlString), ["https://kept.example"])
    }

    func testUnknownSessionShapeWarnsButKeepsBookmarks() throws {
        try writeBookmarks()
        try writePlist(["Unrecognised": ["shape"]], named: "LastSession.plist")

        let result = try parse()

        XCTAssertTrue(result.data.regularTabs.isEmpty)
        XCTAssertEqual(result.data.bookmarks.first?.totalBookmarkCount, 1)
        XCTAssertTrue(result.warnings.contains { $0.contains("no open tabs were recognised") })
    }

    /// The remedy for a protected folder is a System Settings toggle, so it must
    /// not be reported as a missing or corrupt file.
    func testUnreadableBookmarksReportsFullDiskAccess() throws {
        try writeBookmarks()
        let file = safari.appendingPathComponent("Bookmarks.plist")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        XCTAssertThrowsError(try parse()) { error in
            XCTAssertEqual(error as? SumiSafariImportParser.ParseError, .fullDiskAccessRequired)
        }
    }

    // MARK: - Helpers

    private func parse() throws -> SumiSafariImportResult {
        try SumiSafariImportParser(browserName: "Safari", safariDirectoryURL: safari).parseWithDiagnostics()
    }

    private func writeBookmarks() throws {
        try writePlist(
            [
                "WebBookmarkType": "WebBookmarkTypeList",
                "Children": [[
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "BookmarksBar",
                    "Children": [[
                        "WebBookmarkType": "WebBookmarkTypeLeaf",
                        "URLString": "https://apple.example",
                        "URIDictionary": ["title": "Apple"],
                    ]],
                ]],
            ],
            named: "Bookmarks.plist"
        )
    }

    private func writePlist(_ object: [String: Any], named name: String) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: object,
            format: .binary,
            options: 0
        )
        try data.write(to: safari.appendingPathComponent(name))
    }
}
