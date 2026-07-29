import SQLite3
import WebKit
import XCTest

@testable import Sumi

final class SumiImportBulkStagingTests: XCTestCase {
    private var root: URL!
    private var staging: SumiImportBulkStagingStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiImportBulkStagingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        staging = SumiImportBulkStagingStore(rootDirectory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRoundTripsRecordsThroughNDJSON() throws {
        let directory = try staging.makeStagingDirectory(for: UUID())
        let file = directory.appendingPathComponent("history.ndjson")
        let visits = (0..<1250).map { index in
            SumiStagedHistoryVisit(
                urlString: "https://example.com/\(index)",
                title: "Page \(index)",
                visitedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let written = try staging.write(visits, to: file)
        XCTAssertEqual(written.count, 1250)

        var readBack: [SumiStagedHistoryVisit] = []
        var chunkSizes: [Int] = []
        try staging.read(SumiStagedHistoryVisit.self, from: file, chunkSize: 500) { chunk in
            chunkSizes.append(chunk.count)
            readBack.append(contentsOf: chunk)
        }

        XCTAssertEqual(readBack, visits)
        XCTAssertEqual(chunkSizes, [500, 500, 250], "records must arrive in bounded chunks, not one array")
    }

    /// A truncated staging file should cost its last record, not the import.
    func testSkipsMalformedLinesInsteadOfFailing() throws {
        let directory = try staging.makeStagingDirectory(for: UUID())
        let file = directory.appendingPathComponent("history.ndjson")
        let good = SumiStagedHistoryVisit(
            urlString: "https://kept.example",
            title: "Kept",
            visitedAt: Date(timeIntervalSince1970: 1)
        )
        var payload = try JSONEncoder().encode(good)
        payload.append(0x0A)
        payload.append(contentsOf: Data(#"{"urlString":"https://broken"#.utf8))
        payload.append(0x0A)
        try payload.write(to: file)

        var readBack: [SumiStagedHistoryVisit] = []
        try staging.read(SumiStagedHistoryVisit.self, from: file, chunkSize: 10) { readBack.append(contentsOf: $0) }

        XCTAssertEqual(readBack, [good])
    }

    func testManifestRejectsAnUnsupportedVersion() throws {
        let id = UUID()
        let directory = try staging.makeStagingDirectory(for: id)
        let manifest = SumiImportBulkStagingManifest(
            version: SumiImportBulkStagingManifest.currentVersion + 1,
            stagingID: id,
            sourceKind: .chromium,
            entries: []
        )
        try JSONEncoder().encode(manifest)
            .write(to: directory.appendingPathComponent("manifest.json"))

        XCTAssertThrowsError(try staging.loadManifest(for: id))
    }

    func testManifestRoundTrips() throws {
        let id = UUID()
        _ = try staging.makeStagingDirectory(for: id)
        let manifest = SumiImportBulkStagingManifest(
            stagingID: id,
            sourceKind: .chromium,
            entries: [
                .init(
                    kind: .history,
                    sourceProfileKey: "Default",
                    fileName: "history.ndjson",
                    blobDirectoryName: nil,
                    recordCount: 12,
                    byteCount: 340,
                    skipped: 1,
                    skipReasons: ["capped"]
                ),
            ]
        )
        try staging.writeManifest(manifest)

        let loaded = try staging.loadManifest(for: id)

        XCTAssertEqual(loaded, manifest)
        XCTAssertEqual(loaded.recordCount(for: .history), 12)
        XCTAssertEqual(loaded.skippedCount(for: .history), 1)
        XCTAssertEqual(loaded.kinds, [.history])
    }

    func testValidationRejectsBrowsingDataThatDisappearedAfterPreview() throws {
        let id = UUID()
        let directory = try staging.makeStagingDirectory(for: id)
        let fileName = "history.ndjson"
        let file = directory.appendingPathComponent(fileName)
        _ = FileManager.default.createFile(atPath: file.path, contents: Data())
        let manifest = SumiImportBulkStagingManifest(
            stagingID: id,
            sourceKind: .chromium,
            entries: [
                .init(
                    kind: .history,
                    sourceProfileKey: "Default",
                    fileName: fileName,
                    blobDirectoryName: nil,
                    recordCount: 0,
                    byteCount: 0,
                    skipped: 0,
                    skipReasons: []
                ),
            ]
        )
        try staging.writeManifest(manifest)

        XCTAssertNoThrow(try staging.validate(manifest, kinds: [.history]))
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try staging.validate(manifest, kinds: [.history]))
    }

    /// Staging outlives a crash, so anything the journal no longer references
    /// must be swept rather than accumulating forever.
    func testSweepsOrphanedStagingDirectoriesButKeepsLiveOnes() throws {
        let live = UUID()
        let orphan = UUID()
        _ = try staging.makeStagingDirectory(for: live)
        _ = try staging.makeStagingDirectory(for: orphan)
        // A non-UUID neighbour must be left alone.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-staging-directory"),
            withIntermediateDirectories: true
        )

        staging.sweepOrphans(keeping: [live])

        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.directory(for: live).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.directory(for: orphan).path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("not-a-staging-directory").path)
        )
    }

    /// Bulk kinds must never widen what a `.sumibackup` claims to contain.
    func testBulkKindsAreNotImportCategories() {
        let categoryNames = Set(SumiImportCategory.allCases.map(\.rawValue))
        for kind in SumiImportBulkKind.allCases {
            XCTAssertFalse(categoryNames.contains(kind.rawValue))
        }
    }

    func testAppliesInIncreasingOrderOfIrreversibility() {
        XCTAssertEqual(SumiImportBulkKind.applyOrder, [.cookies, .history, .favicons])
        XCTAssertEqual(Set(SumiImportBulkKind.applyOrder), Set(SumiImportBulkKind.allCases))
    }

    func testFirefoxCookiesRetainTheirContainerPartition() throws {
        let profile = root.appendingPathComponent("abc.default", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let databaseURL = profile.appendingPathComponent("cookies.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(
            sqlite3_exec(
                database,
                """
                CREATE TABLE moz_cookies (
                    host TEXT, name TEXT, value TEXT, path TEXT, expiry INTEGER,
                    isSecure INTEGER, isHttpOnly INTEGER, originAttributes TEXT
                );
                INSERT INTO moz_cookies VALUES
                    ('.example.com', 'default', 'a', '/', 4102444800000, 1, 1, ''),
                    ('.example.com', 'work', 'b', '/', 4102444800000, 1, 0, '^userContextId=2'),
                    ('.example.com', 'partitioned', 'c', '/', 4102444800000, 1, 0, '^partitionKey=%28https%2Cexample.com%29');
                """,
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        let file = root.appendingPathComponent("cookies.ndjson")

        let extraction = try SumiImportCookieExtractor(
            family: .firefox,
            profileURL: profile
        ).stage(to: file, staging: staging)
        var cookies: [SumiStagedCookie] = []
        try staging.read(SumiStagedCookie.self, from: file, chunkSize: 10) {
            cookies.append(contentsOf: $0)
        }

        XCTAssertEqual(extraction.recordCount, 2)
        XCTAssertEqual(extraction.skipped, 1)
        XCTAssertEqual(
            extraction.skipReasons,
            ["Partitioned Mozilla cookies cannot be represented by WebKit and were skipped."]
        )
        XCTAssertEqual(
            cookies.compactMap(\.sourceProfileKey),
            ["abc.default|userContextId=0", "abc.default|userContextId=2"]
        )
    }

    func testFirefoxCookieStagingExcludesContainersNotImportedAsProfiles() throws {
        let profile = root.appendingPathComponent("abc.default", isDirectory: true)
        try FileManager.default.createDirectory(
            at: profile,
            withIntermediateDirectories: true
        )
        let databaseURL = profile.appendingPathComponent("cookies.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                """
                CREATE TABLE moz_cookies (
                    host TEXT, name TEXT, value TEXT, path TEXT, expiry INTEGER,
                    isSecure INTEGER, isHttpOnly INTEGER, originAttributes TEXT
                );
                INSERT INTO moz_cookies VALUES
                    ('.example.com', 'default', 'a', '/', 4102444800000, 1, 1, ''),
                    ('.example.com', 'work', 'b', '/', 4102444800000, 1, 0, '^userContextId=2'),
                    ('.example.com', 'unused', 'c', '/', 4102444800000, 1, 0, '^userContextId=3');
                """,
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let browser = SumiDetectedBrowser(
            id: "firefox",
            displayName: "Firefox",
            family: .firefox,
            sourceKind: .firefox,
            dataRoot: root,
            bundleIdentifiers: ["org.mozilla.firefox"],
            capabilities: [.cookies],
            profiles: [],
            accessIssue: nil
        )
        let selection = SumiDetectedBrowserProfile(
            id: "firefox|abc.default",
            displayName: "default",
            directoryURL: profile,
            sourceDirectoryKey: "abc.default"
        )
        let staged = try XCTUnwrap(
            SumiImportBulkStagingCoordinator(staging: staging).stage(
                browser: browser,
                profile: selection,
                kinds: [.cookies],
                sourceProfileKeys: [
                    "abc.default|userContextId=0",
                    "abc.default|userContextId=2",
                ]
            )
        )
        let manifest = try XCTUnwrap(staged.manifest)
        let entry = try XCTUnwrap(manifest.entries.first)
        var cookies: [SumiStagedCookie] = []
        try staging.read(
            SumiStagedCookie.self,
            from: staging.directory(for: manifest.stagingID)
                .appendingPathComponent(entry.fileName),
            chunkSize: 10
        ) {
            cookies.append(contentsOf: $0)
        }

        XCTAssertEqual(cookies.map(\.name), ["default", "work"])
    }

    @MainActor
    func testCookieInstallerWritesSessionCookieIntoWebKitProfileStore() async throws {
        let profileID = UUID()
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let installer = SumiProfileCookieInstallationService { requestedProfileID in
            requestedProfileID == profileID ? dataStore : nil
        }
        let staged = SumiStagedCookie(
            name: "SID",
            value: "session-token",
            domain: ".google.com",
            path: "/",
            expiresAt: Date(timeIntervalSinceNow: 3_600),
            isSecure: true,
            isHTTPOnly: true
        )

        let receipt = try await installer.install(
            [staged],
            profileId: profileID,
            overwriteExisting: true
        )
        let allCookies = await dataStore.httpCookieStore.allCookies()
        let stored = try XCTUnwrap(
            allCookies.first {
                $0.name == staged.name && $0.domain == staged.domain
            }
        )

        XCTAssertEqual(stored.value, staged.value)
        XCTAssertTrue(stored.isSecure)
        XCTAssertTrue(stored.isHTTPOnly)
        XCTAssertEqual(receipt.installedIdentities, [staged.identity])
    }

    func testArcBulkDataComesFromEachUsedUserDataProfile() throws {
        let arcRoot = root.appendingPathComponent("Arc", isDirectory: true)
        let userData = arcRoot.appendingPathComponent("User Data", isDirectory: true)
        for name in ["Default", "Profile 1"] {
            let profile = userData.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            let historyURL = profile.appendingPathComponent("History")
            var database: OpaquePointer?
            XCTAssertEqual(sqlite3_open(historyURL.path, &database), SQLITE_OK)
            XCTAssertEqual(
                sqlite3_exec(
                    database,
                    """
                    CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT);
                    CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER);
                    INSERT INTO urls VALUES (1, 'https://\(name.replacingOccurrences(of: " ", with: "-")).example', '\(name)');
                    INSERT INTO visits VALUES (1, 1, 13344473600000000);
                    """,
                    nil,
                    nil,
                    nil
                ),
                SQLITE_OK
            )
            sqlite3_close(database)
        }
        let browser = SumiDetectedBrowser(
            id: "arc",
            displayName: "Arc",
            family: .arc,
            sourceKind: .arc,
            dataRoot: arcRoot,
            bundleIdentifiers: ["company.thebrowser.Browser"],
            capabilities: [.history],
            profiles: [],
            accessIssue: nil
        )
        let selection = SumiDetectedBrowserProfile(
            id: "arc|default",
            displayName: "All spaces",
            directoryURL: arcRoot,
            sourceDirectoryKey: "Default"
        )

        let staged = try XCTUnwrap(
            SumiImportBulkStagingCoordinator(staging: staging).stage(
                browser: browser,
                profile: selection,
                kinds: [.history],
                sourceProfileKeys: ["Profile 1"]
            )
        )
        let manifest = try XCTUnwrap(staged.manifest)

        XCTAssertEqual(manifest.entries.count, 1)
        XCTAssertEqual(manifest.entries.first?.sourceProfileKey, "Profile 1")
        XCTAssertEqual(manifest.entries.first?.recordCount, 1)
    }

    @MainActor
    func testCookieApplyRoutesEachMozillaPartitionToItsSumiProfile() async throws {
        let stagingID = UUID()
        let directory = try staging.makeStagingDirectory(for: stagingID)
        let file = directory.appendingPathComponent("cookies.ndjson")
        let cookies = [
            SumiStagedCookie(
                name: "default",
                value: "a",
                domain: ".example.com",
                path: "/",
                expiresAt: Date(timeIntervalSince1970: 4_102_444_800),
                isSecure: true,
                isHTTPOnly: true,
                sourceProfileKey: "abc.default|userContextId=0"
            ),
            SumiStagedCookie(
                name: "work",
                value: "b",
                domain: ".example.com",
                path: "/",
                expiresAt: Date(timeIntervalSince1970: 4_102_444_800),
                isSecure: true,
                isHTTPOnly: true,
                sourceProfileKey: "abc.default|userContextId=2"
            ),
        ]
        _ = try staging.write(cookies, to: file)
        let manifest = SumiImportBulkStagingManifest(
            stagingID: stagingID,
            sourceKind: .firefox,
            entries: [
                .init(
                    kind: .cookies,
                    sourceProfileKey: "abc.default|userContextId=0",
                    fileName: file.lastPathComponent,
                    blobDirectoryName: nil,
                    recordCount: cookies.count,
                    byteCount: 0,
                    skipped: 0,
                    skipReasons: []
                ),
            ]
        )
        let defaultProfile = UUID()
        let workProfile = UUID()
        let installer = RecordingCookieBulkInstaller()
        let coordinator = SumiImportBulkApplyCoordinator(
            staging: staging,
            installer: installer
        )
        var receipt = SumiImportBulkReceipt()

        try await coordinator.apply(
            manifest: manifest,
            kinds: [.cookies],
            profileIDsBySourceKey: [
                "abc.default|userContextId=0": defaultProfile,
                "abc.default|userContextId=2": workProfile,
            ],
            into: &receipt
        )

        XCTAssertEqual(installer.cookiesByProfile[defaultProfile]?.map(\.name), ["default"])
        XCTAssertEqual(installer.cookiesByProfile[workProfile]?.map(\.name), ["work"])
    }

    @MainActor
    func testCookieApplyFailsInsteadOfMergingAnUnmappedJar() async throws {
        let stagingID = UUID()
        let directory = try staging.makeStagingDirectory(for: stagingID)
        let file = directory.appendingPathComponent("cookies.ndjson")
        let cookie = SumiStagedCookie(
            name: "session",
            value: "secret",
            domain: ".example.com",
            path: "/",
            expiresAt: nil,
            isSecure: true,
            isHTTPOnly: true,
            sourceProfileKey: "source|userContextId=2"
        )
        _ = try staging.write([cookie], to: file)
        let manifest = SumiImportBulkStagingManifest(
            stagingID: stagingID,
            sourceKind: .firefox,
            entries: [
                .init(
                    kind: .cookies,
                    sourceProfileKey: "source|userContextId=0",
                    fileName: file.lastPathComponent,
                    blobDirectoryName: nil,
                    recordCount: 1,
                    byteCount: 0,
                    skipped: 0,
                    skipReasons: []
                ),
            ]
        )
        let coordinator = SumiImportBulkApplyCoordinator(
            staging: staging,
            installer: RecordingCookieBulkInstaller()
        )
        var receipt = SumiImportBulkReceipt()

        do {
            try await coordinator.apply(
                manifest: manifest,
                kinds: [.cookies],
                profileIDsBySourceKey: ["source|userContextId=0": UUID()],
                into: &receipt
            )
            XCTFail("An isolated cookie jar must never fall back to another profile")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No target profile"))
        }
    }

    @MainActor
    func testHistoryRefreshesOnceAfterAllChunks() async throws {
        let stagingID = UUID()
        let directory = try staging.makeStagingDirectory(for: stagingID)
        let file = directory.appendingPathComponent("history.ndjson")
        let visits = (0..<1_001).map { index in
            SumiStagedHistoryVisit(
                urlString: "https://example.com/\(index)",
                title: "\(index)",
                visitedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        _ = try staging.write(visits, to: file)
        let manifest = SumiImportBulkStagingManifest(
            stagingID: stagingID,
            sourceKind: .chromium,
            entries: [
                .init(
                    kind: .history,
                    sourceProfileKey: "Default",
                    fileName: file.lastPathComponent,
                    blobDirectoryName: nil,
                    recordCount: visits.count,
                    byteCount: 0,
                    skipped: 0,
                    skipReasons: []
                ),
            ]
        )
        let installer = RecordingCookieBulkInstaller()
        let coordinator = SumiImportBulkApplyCoordinator(
            staging: staging,
            installer: installer
        )
        var receipt = SumiImportBulkReceipt()

        try await coordinator.apply(
            manifest: manifest,
            kinds: [.history],
            profileIDsBySourceKey: ["Default": UUID()],
            into: &receipt
        )

        XCTAssertEqual(receipt.history.count, 3)
        XCTAssertEqual(installer.historyRefreshCount, 1)
    }

    func testParsesSafariBinaryCookies() throws {
        let payload = makeSafariBinaryCookiesFixture()

        let cookies = try SumiSafariBinaryCookiesParser.parse(payload)

        let cookie = try XCTUnwrap(cookies.first)
        XCTAssertEqual(cookie.name, "session")
        XCTAssertEqual(cookie.value, "abc123")
        XCTAssertEqual(cookie.domain, ".example.com")
        XCTAssertEqual(cookie.path, "/")
        XCTAssertTrue(cookie.isSecure)
        XCTAssertTrue(cookie.isHTTPOnly)
        XCTAssertEqual(cookies.count, 1)
    }

    private func makeSafariBinaryCookiesFixture() -> Data {
        let strings = [
            Data(".example.com\0".utf8),
            Data("session\0".utf8),
            Data("/\0".utf8),
            Data("abc123\0".utf8),
        ]
        let headerSize = 56
        let offsets = [
            headerSize,
            headerSize + strings[0].count,
            headerSize + strings[0].count + strings[1].count,
            headerSize + strings[0].count + strings[1].count + strings[2].count,
        ]
        var cookie = Data()
        append(UInt32(headerSize + strings.reduce(0) { $0 + $1.count }), to: &cookie)
        append(UInt32(0), to: &cookie)
        append(UInt32(5), to: &cookie)
        append(UInt32(0), to: &cookie)
        offsets.forEach { append(UInt32($0), to: &cookie) }
        append(UInt64(0), to: &cookie)
        append(Date(timeIntervalSince1970: 4_102_444_800).timeIntervalSince1970 - 978_307_200, to: &cookie)
        append(Double(0), to: &cookie)
        strings.forEach { cookie.append($0) }

        var page = Data([0, 0, 1, 0])
        append(UInt32(1), to: &page)
        append(UInt32(12), to: &page)
        page.append(cookie)

        var archive = Data("cook".utf8)
        append(UInt32(1).bigEndian, to: &archive)
        append(UInt32(page.count).bigEndian, to: &archive)
        archive.append(page)
        return archive
    }

    private func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func append(_ value: UInt64, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func append(_ value: Double, to data: inout Data) {
        append(value.bitPattern, to: &data)
    }
}

@MainActor
private final class RecordingCookieBulkInstaller: SumiImportBulkInstalling {
    var cookiesByProfile: [UUID: [SumiStagedCookie]] = [:]
    var historyRefreshCount = 0

    func installHistory(
        _ visits: [HistoryImportedVisit],
        profileId: UUID?
    ) async throws -> HistoryImportedVisitWriter.Receipt {
        HistoryImportedVisitWriter.Receipt()
    }

    func rollbackHistory(_ receipt: HistoryImportedVisitWriter.Receipt) async throws {}

    func didMutateHistory() async {
        historyRefreshCount += 1
    }

    func installFavicons(_ favicons: [SumiImportFaviconPayload], profileId: UUID?) async {}

    func installCookies(
        _ cookies: [SumiStagedCookie],
        profileId: UUID
    ) async throws -> SumiCookieInstallationReceipt {
        cookiesByProfile[profileId, default: []].append(contentsOf: cookies)
        return SumiCookieInstallationReceipt(
            installedIdentities: Set(cookies.map(\.identity)),
            replaced: []
        )
    }

    func rollbackCookies(
        _ receipt: SumiCookieInstallationReceipt,
        profileId: UUID
    ) async {}
}
