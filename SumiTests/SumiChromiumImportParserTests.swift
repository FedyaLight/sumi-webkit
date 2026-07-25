import XCTest

@testable import Sumi

final class SumiChromiumImportParserTests: XCTestCase {
    private var userData: URL!

    override func setUpWithError() throws {
        userData = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiChromiumImportParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: userData)
    }

    func testEachProfileBecomesAProfileAndASpace() throws {
        try makeProfile("Default", displayName: "Personal")
        try makeProfile("Profile 1", displayName: "Work")

        let result = try parse()

        XCTAssertEqual(result.data.profiles.map(\.name), ["Personal", "Work"])
        XCTAssertEqual(result.data.spaces.map(\.name), ["Personal", "Work"])
        // The join key for history/cookies/favicons is the directory, not the
        // display name, which the user can rename at any time.
        XCTAssertEqual(result.data.profiles.map(\.sourceDirectoryKey), ["Default", "Profile 1"])
        XCTAssertEqual(
            result.data.spaces.map(\.profileId),
            result.data.profiles.map(\.id)
        )
    }

    func testSessionPinnedTabsBecomePinnedAndOthersBecomeRegularTabs() throws {
        var session = SNSSFixture()
        session.pinnedTab(id: 10, url: "https://pinned.example", title: "Pinned")
        session.openTab(id: 11, url: "https://open.example", title: "Open")
        try makeProfile("Default", displayName: "Personal", session: session.data)

        let result = try parse()

        XCTAssertEqual(result.data.pinnedLaunchers.map(\.urlString), ["https://pinned.example"])
        XCTAssertEqual(result.data.regularTabs.map(\.urlString), ["https://open.example"])
        XCTAssertEqual(result.data.pinnedLaunchers.first?.spaceId, result.data.spaces.first?.id)
    }

    /// Bookmarks and sidebar tabs are separate channels. Deriving the sidebar
    /// from bookmarks would dump every bookmark the user ever made into it.
    func testBookmarksDoNotBecomeSidebarTabs() throws {
        try makeProfile("Default", displayName: "Personal", bookmarkCount: 25)

        let result = try parse()

        XCTAssertTrue(result.data.pinnedLaunchers.isEmpty)
        XCTAssertTrue(result.data.regularTabs.isEmpty)
        XCTAssertEqual(result.data.bookmarks.first?.totalBookmarkCount, 25)
    }

    func testSkipsInternalBrowserURLsInBookmarks() throws {
        try makeProfile(
            "Default",
            displayName: "Personal",
            bookmarkURLs: ["https://kept.example", "chrome://settings", "javascript:alert(1)"]
        )

        let result = try parse()

        XCTAssertEqual(result.data.bookmarks.first?.totalBookmarkCount, 1)
    }

    /// An unreadable session must cost the user their tabs, not the import.
    func testUnreadableSessionWarnsButStillImportsBookmarks() throws {
        try makeProfile("Default", displayName: "Personal", bookmarkCount: 3)
        let sessions = userData.appendingPathComponent("Default/Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data("not a session file".utf8).write(to: sessions.appendingPathComponent("Session_1"))

        let result = try parse()

        XCTAssertEqual(result.data.bookmarks.first?.totalBookmarkCount, 3)
        XCTAssertTrue(result.warnings.contains { $0.contains("session file could not be read") })
    }

    func testThrowsWhenNoProfilesExist() {
        XCTAssertThrowsError(try parse())
    }

    // MARK: - Helpers

    private func parse() throws -> SumiChromiumImportResult {
        try SumiChromiumImportParser(browserName: "Chrome", userDataURL: userData).parseWithDiagnostics()
    }

    private func makeProfile(
        _ directory: String,
        displayName: String,
        bookmarkCount: Int = 0,
        bookmarkURLs: [String]? = nil,
        session: Data? = nil
    ) throws {
        let profile = userData.appendingPathComponent(directory, isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)

        let urls = bookmarkURLs ?? (0..<bookmarkCount).map { "https://example.com/\($0)" }
        let children = urls.map { ["type": "url", "name": "Bookmark", "url": $0] }
        try JSONSerialization
            .data(withJSONObject: ["roots": ["bookmark_bar": ["children": children]]])
            .write(to: profile.appendingPathComponent("Bookmarks"))

        var localState = (try? JSONSerialization.jsonObject(
            with: Data(contentsOf: userData.appendingPathComponent("Local State"))
        ) as? [String: Any]) ?? [:]
        var profileSection = localState["profile"] as? [String: Any] ?? [:]
        var cache = profileSection["info_cache"] as? [String: Any] ?? [:]
        cache[directory] = ["name": displayName]
        profileSection["info_cache"] = cache
        localState["profile"] = profileSection
        try JSONSerialization.data(withJSONObject: localState)
            .write(to: userData.appendingPathComponent("Local State"))

        if let session {
            let sessions = profile.appendingPathComponent("Sessions", isDirectory: true)
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            try session.write(to: sessions.appendingPathComponent("Session_13400000000000000"))
        }
    }
}

/// Minimal SNSS writer; the byte layout is covered in detail by
/// `SumiChromiumSessionReaderTests`.
private struct SNSSFixture {
    private(set) var data = Data("SNSS".utf8) + Data([3, 0, 0, 0])

    mutating func pinnedTab(id: Int32, url: String, title: String) {
        openTab(id: id, url: url, title: title)
        append(command: 12, payload: int32(id) + int32(1))
    }

    mutating func openTab(id: Int32, url: String, title: String) {
        append(command: 0, payload: int32(1) + int32(id))
        var pickle = int32(id) + int32(0)
        let urlBytes = Data(url.utf8)
        pickle += int32(Int32(urlBytes.count)) + urlBytes + padding(urlBytes.count)
        let units = Array(title.utf16)
        var titleBytes = Data()
        for unit in units {
            titleBytes.append(UInt8(unit & 0xFF))
            titleBytes.append(UInt8(unit >> 8))
        }
        pickle += int32(Int32(units.count)) + titleBytes + padding(titleBytes.count)
        append(command: 6, payload: int32(Int32(pickle.count)) + pickle)
    }

    private mutating func append(command: UInt8, payload: Data) {
        let size = UInt16(payload.count + 1)
        data.append(UInt8(size & 0xFF))
        data.append(UInt8(size >> 8))
        data.append(command)
        data.append(payload)
    }

    private func int32(_ value: Int32) -> Data {
        Data(withUnsafeBytes(of: value.littleEndian, Array.init))
    }

    private func padding(_ count: Int) -> Data {
        Data(repeating: 0, count: (4 - (count % 4)) % 4)
    }
}
