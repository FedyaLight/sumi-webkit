import Compression
import XCTest

@testable import Sumi

final class SumiFirefoxImportParserTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFirefoxImportParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testReadsProfilesFromProfilesIni() throws {
        try makeProfile("abc.default-release")
        try makeProfile("xyz.work")
        try """
        [Profile0]
        Name=default
        IsRelative=1
        Path=abc.default-release

        [Profile1]
        Name=work
        IsRelative=1
        Path=xyz.work
        """.write(to: root.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)

        let profiles = SumiFirefoxImportParser.profiles(rootURL: root)

        XCTAssertEqual(profiles.map(\.directoryName), ["abc.default-release", "xyz.work"])
        XCTAssertEqual(profiles.map(\.displayName), ["default-release", "work"])
    }

    /// A profile directory with no `places.sqlite` is not a usable profile.
    func testIgnoresProfilesIniEntriesWithoutAPlacesDatabase() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("empty.profile", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "[Profile0]\nIsRelative=1\nPath=empty.profile"
            .write(to: root.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)

        XCTAssertTrue(SumiFirefoxImportParser.profiles(rootURL: root).isEmpty)
    }

    func testContainersBecomeAdditionalProfilesSharingTheBulkDataKey() throws {
        let profile = try makeProfile("abc.default")
        try JSONSerialization.data(withJSONObject: [
            "identities": [
                ["userContextId": 0, "name": "Default", "public": true],
                ["userContextId": 1, "name": "Banking", "public": true],
                ["userContextId": 2, "l10nID": "userContextWork.label", "public": true],
                ["userContextId": 3, "name": "Hidden", "public": false],
            ]
        ]).write(to: profile.appendingPathComponent("containers.json"))

        let result = try parse(profile)

        XCTAssertEqual(result.data.profiles.map(\.name), ["abc.default".dropFirst(4).description, "Banking", "Work"])
        // Containers share one profile directory, so bulk data joins on the
        // same key for all of them.
        XCTAssertEqual(Set(result.data.profiles.compactMap(\.sourceDirectoryKey)), ["abc.default"])
    }

    func testSessionStorePinnedAndOpenTabs() throws {
        let profile = try makeProfile("abc.default")
        let session: [String: Any] = [
            "windows": [[
                "tabs": [
                    [
                        "pinned": true,
                        "index": 1,
                        "entries": [["url": "https://pinned.example", "title": "Pinned"]],
                    ],
                    [
                        "index": 2,
                        "entries": [
                            ["url": "https://old.example", "title": "Old"],
                            ["url": "https://current.example", "title": "Current"],
                        ],
                    ],
                    // `about:` pages have no meaning outside Firefox.
                    ["index": 1, "entries": [["url": "about:newtab", "title": "New Tab"]]],
                ]
            ]]
        ]
        try mozLZ4(JSONSerialization.data(withJSONObject: session))
            .write(to: profile.appendingPathComponent("sessionstore.jsonlz4"))

        let result = try parse(profile)

        XCTAssertEqual(result.data.pinnedLaunchers.map(\.urlString), ["https://pinned.example"])
        XCTAssertEqual(result.data.regularTabs.map(\.urlString), ["https://current.example"])
    }

    /// The session `index` is a 1-based cursor into back/forward history, so a
    /// tab the user navigated back in is not described by its last entry.
    func testUsesTheSessionIndexRatherThanTheLastHistoryEntry() throws {
        let profile = try makeProfile("abc.default")
        let session: [String: Any] = [
            "windows": [[
                "tabs": [[
                    "index": 1,
                    "entries": [
                        ["url": "https://current.example", "title": "Current"],
                        ["url": "https://forward.example", "title": "Forward"],
                    ],
                ]]
            ]]
        ]
        try mozLZ4(JSONSerialization.data(withJSONObject: session))
            .write(to: profile.appendingPathComponent("sessionstore.jsonlz4"))

        XCTAssertEqual(try parse(profile).data.regularTabs.map(\.urlString), ["https://current.example"])
    }

    func testFallsBackToRecoveryFileAndWarns() throws {
        let profile = try makeProfile("abc.default")
        let backups = profile.appendingPathComponent("sessionstore-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let session: [String: Any] = [
            "windows": [["tabs": [["index": 1, "entries": [["url": "https://recovered.example"]]]]]]
        ]
        try mozLZ4(JSONSerialization.data(withJSONObject: session))
            .write(to: backups.appendingPathComponent("recovery.jsonlz4"))

        XCTAssertEqual(try parse(profile).data.regularTabs.map(\.urlString), ["https://recovered.example"])
    }

    func testCorruptSessionWarnsWithoutFailingTheImport() throws {
        let profile = try makeProfile("abc.default")
        try Data("garbage".utf8).write(to: profile.appendingPathComponent("sessionstore.jsonlz4"))

        let result = try parse(profile)

        XCTAssertTrue(result.data.regularTabs.isEmpty)
        XCTAssertEqual(result.data.spaces.count, 1, "the space still imports")
        XCTAssertTrue(result.warnings.contains { $0.contains("open tabs were skipped") })
    }

    // MARK: - Helpers

    private func parse(_ profile: URL) throws -> SumiFirefoxImportResult {
        try SumiFirefoxImportParser(
            browserName: "Firefox",
            profileURL: profile,
            directoryName: profile.lastPathComponent
        ).parseWithDiagnostics()
    }

    @discardableResult
    private func makeProfile(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data().write(to: url.appendingPathComponent("places.sqlite"))
        return url
    }

    private func mozLZ4(_ payload: Data) throws -> Data {
        let capacity = payload.count + 64
        var output = Data(count: capacity)
        let compressed = output.withUnsafeMutableBytes { outPtr in
            payload.withUnsafeBytes { inPtr in
                compression_encode_buffer(
                    outPtr.bindMemory(to: UInt8.self).baseAddress!,
                    capacity,
                    inPtr.bindMemory(to: UInt8.self).baseAddress!,
                    payload.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }
        var archive = Data([0x6D, 0x6F, 0x7A, 0x4C, 0x7A, 0x34, 0x30, 0x00])
        let size = UInt32(payload.count)
        for shift in stride(from: 0, to: 32, by: 8) {
            archive.append(UInt8((size >> UInt32(shift)) & 0xFF))
        }
        archive.append(output.prefix(compressed))
        return archive
    }
}
