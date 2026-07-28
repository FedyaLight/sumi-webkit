import XCTest

@testable import Sumi

@MainActor
final class SumiImportTransactionDatabaseJournalTests: XCTestCase {
    func testCleanStartupAdmissionDoesNotEnterRecovery() throws {
        let database = try SumiDatabase.inMemory()
        let admission = SumiStartupAdmission.evaluate(
            preflight: .ready,
            profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
                database: database
            ),
            importJournal: SumiImportTransactionDatabaseJournal(
                database: database
            )
        )

        guard case .ready = admission else {
            return XCTFail("A clean database should start immediately")
        }
    }

    func testPendingImportJournalRequiresStartupRecovery() async throws {
        let database = try SumiDatabase.inMemory()
        let journal = SumiImportTransactionDatabaseJournal(database: database)
        try await journal.save(record(phase: .prepared))

        let admission = SumiStartupAdmission.evaluate(
            preflight: .ready,
            profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
                database: database
            ),
            importJournal: journal
        )

        guard case .recoveryRequired = admission else {
            return XCTFail("A pending import must enter recovery")
        }
    }

    func testFailedRetirementPreflightFailsClosed() throws {
        let database = try SumiDatabase.inMemory()
        let admission = SumiStartupAdmission.evaluate(
            preflight: .failed(message: "Unreadable retirement ledger"),
            profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
                database: database
            ),
            importJournal: SumiImportTransactionDatabaseJournal(
                database: database
            )
        )

        guard case .failed(let message) = admission else {
            return XCTFail("An unreadable retirement ledger must fail closed")
        }
        XCTAssertEqual(message, "Unreadable retirement ledger")
    }

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
