import SQLite3
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
                )
            ]
        )
        try staging.writeManifest(manifest)

        let loaded = try staging.loadManifest(for: id)

        XCTAssertEqual(loaded, manifest)
        XCTAssertEqual(loaded.recordCount(for: .history), 12)
        XCTAssertEqual(loaded.skippedCount(for: .history), 1)
        XCTAssertEqual(loaded.kinds, [.history])
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
        XCTAssertEqual(SumiImportBulkKind.applyOrder, [.history, .favicons, .cookies])
        XCTAssertEqual(Set(SumiImportBulkKind.applyOrder), Set(SumiImportBulkKind.allCases))
    }
}
