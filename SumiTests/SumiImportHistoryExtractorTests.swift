import SQLite3
import XCTest

@testable import Sumi

/// Each browser stores time against a different origin and unit. Getting one
/// wrong silently shifts a user's whole history by decades, so every epoch is
/// pinned against a known instant.
final class SumiImportHistoryExtractorTests: XCTestCase {
    private var root: URL!
    private var staging: SumiImportBulkStagingStore!
    /// 2024-01-01T00:00:00Z, expressed in each browser's own units below.
    private let instant = Date(timeIntervalSince1970: 1_704_067_200)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiImportHistoryExtractorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        staging = SumiImportBulkStagingStore(rootDirectory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testChromiumVisitsUseTheWindowsEpoch() throws {
        let profile = try makeProfile("chrome")
        // Microseconds since 1601-01-01.
        let chromeTime = Int64((1_704_067_200 + 11_644_473_600) * 1_000_000)
        try makeDatabase(at: profile.appendingPathComponent("History"), sql: """
            CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT);
            CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER);
            INSERT INTO urls VALUES (1, 'https://example.com/page', 'Example');
            INSERT INTO urls VALUES (2, 'chrome://settings', 'Settings');
            INSERT INTO visits VALUES (1, 1, \(chromeTime));
            INSERT INTO visits VALUES (2, 2, \(chromeTime));
            """)

        let visits = try extract(family: .chromium, profile: profile)

        XCTAssertEqual(visits.map(\.urlString), ["https://example.com/page"], "internal pages are not history")
        XCTAssertEqual(visits.first?.visitedAt.timeIntervalSince1970 ?? 0, instant.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(visits.first?.title, "Example")
    }

    func testFirefoxVisitsUseUnixMicroseconds() throws {
        let profile = try makeProfile("firefox")
        try makeDatabase(at: profile.appendingPathComponent("places.sqlite"), sql: """
            CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT);
            CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, place_id INTEGER, visit_date INTEGER);
            INSERT INTO moz_places VALUES (1, 'https://example.com/page', 'Example');
            INSERT INTO moz_historyvisits VALUES (1, 1, \(Int64(1_704_067_200) * 1_000_000));
            """)

        let visits = try extract(family: .firefox, profile: profile)

        XCTAssertEqual(visits.first?.visitedAt.timeIntervalSince1970 ?? 0, instant.timeIntervalSince1970, accuracy: 1)
    }

    func testSafariVisitsUseCoreFoundationAbsoluteTime() throws {
        let profile = try makeProfile("safari")
        // Seconds since 2001-01-01.
        let safariTime = instant.timeIntervalSinceReferenceDate
        try makeDatabase(at: profile.appendingPathComponent("History.db"), sql: """
            CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT);
            CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, title TEXT, visit_time REAL);
            INSERT INTO history_items VALUES (1, 'https://example.com/page');
            INSERT INTO history_visits VALUES (1, 1, 'Example', \(safariTime));
            """)

        let visits = try extract(family: .safari, profile: profile)

        XCTAssertEqual(visits.first?.visitedAt.timeIntervalSince1970 ?? 0, instant.timeIntervalSince1970, accuracy: 1)
    }

    /// A schema that has drifted must yield nothing rather than throwing, so a
    /// browser update cannot break the whole import.
    func testMissingTablesYieldNoVisitsInsteadOfFailing() throws {
        let profile = try makeProfile("chrome")
        try makeDatabase(at: profile.appendingPathComponent("History"), sql: "CREATE TABLE unrelated (id INTEGER);")

        XCTAssertTrue(try extract(family: .chromium, profile: profile).isEmpty)
    }

    func testFirefoxCookieExpiryToleratesBothSecondsAndMilliseconds() {
        // Firefox 108 switched units and both are still found in the wild.
        let seconds = SumiBrowserEpochs.firefoxCookieExpiry(1_704_067_200)
        let milliseconds = SumiBrowserEpochs.firefoxCookieExpiry(1_704_067_200_000)

        XCTAssertEqual(seconds?.timeIntervalSince1970 ?? 0, 1_704_067_200, accuracy: 1)
        XCTAssertEqual(milliseconds?.timeIntervalSince1970 ?? 0, 1_704_067_200, accuracy: 1)
    }

    // MARK: - Helpers

    private func extract(family: SumiBrowserFamily, profile: URL) throws -> [SumiStagedHistoryVisit] {
        let file = try staging.makeStagingDirectory(for: UUID()).appendingPathComponent("history.ndjson")
        _ = try SumiImportHistoryExtractor(family: family, profileURL: profile)
            .stage(to: file, staging: staging)

        var visits: [SumiStagedHistoryVisit] = []
        try staging.read(SumiStagedHistoryVisit.self, from: file) { visits.append(contentsOf: $0) }
        return visits
    }

    private func makeProfile(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDatabase(at url: URL, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }
}
