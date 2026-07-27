import XCTest

@testable import Sumi

@MainActor
final class SumiImportTransactionDatabaseJournalTests: XCTestCase {
    func testJournalPersistsAcrossInstancesAndClearsOnlyAfterCompletion() async throws {
        let database = try SumiDatabase.inMemory()
        let journal = SumiImportTransactionDatabaseJournal(database: database)

        try await journal.save(record(phase: .prepared))
        let freshlyLoaded = try await SumiImportTransactionDatabaseJournal(
            database: database
        ).load()
        XCTAssertEqual(
            freshlyLoaded?.phase,
            .prepared
        )

        try await journal.save(record(phase: .runtimeCommitted))
        try await journal.save(record(phase: .bookmarksCommitted))
        try await journal.save(record(phase: .completed))
        try await journal.clear()

        let cleared = try await journal.load()
        XCTAssertNil(cleared)
    }

    func testJournalRejectsSkippedPhaseAndPrematureClear() async throws {
        let database = try SumiDatabase.inMemory()
        let journal = SumiImportTransactionDatabaseJournal(database: database)
        try await journal.save(record(phase: .prepared))

        await XCTAssertThrowsErrorAsync {
            try await journal.save(self.record(phase: .bookmarksCommitted))
        }
        await XCTAssertThrowsErrorAsync {
            try await journal.clear()
        }

        let retained = try await journal.load()
        XCTAssertEqual(retained?.phase, .prepared)
    }

    private func record(
        phase: SumiImportTransactionPhase
    ) -> SumiImportTransactionJournalRecord {
        SumiImportTransactionJournalRecord(
            phase: phase,
            baseline: SumiPortableData(),
            targetRuntimeData: SumiPortableData(),
            runtimeCheckpoint: nil,
            bookmarkCheckpoint: nil,
            preRestoreBackupURL: nil
        )
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ operation: @MainActor () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
