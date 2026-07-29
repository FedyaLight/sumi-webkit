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

        guard case .ready(let completedRetirements) = admission else {
            return XCTFail("A clean database should start immediately")
        }
        XCTAssertTrue(completedRetirements.isEmpty)
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

    func testCompletedRetirementTombstoneAdmitsBrowserImmediately() throws {
        let database = try SumiDatabase.inMemory()
        let retired = Profile(name: "Retired")
        let retained = Profile(name: "Retained")
        try persistProfiles([retired, retained], in: database)
        try persistRetiredTombstone(
            for: retired,
            fallbackID: retained.id,
            in: database
        )

        let admission = SumiStartupAdmission.evaluate(
            preflight: .ready,
            profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
                database: database
            ),
            importJournal: SumiImportTransactionDatabaseJournal(
                database: database
            )
        )

        guard case .ready(let completedRetirements) = admission else {
            return XCTFail(
                "Completed retirement history must not delay browser presentation"
            )
        }
        XCTAssertEqual(completedRetirements.map(\.snapshot.id), [retired.id])
    }

    func testActiveRetirementStillRequiresRecoveryChrome() throws {
        let database = try SumiDatabase.inMemory()
        let retiring = Profile(name: "Retiring")
        let retained = Profile(name: "Retained")
        try persistProfiles([retiring, retained], in: database)
        let ledger = try ProfileReferenceAdmissionLedger(database: database)
        let token = try ledger.reserve(
            profile: retiring,
            fallbackID: retained.id
        )
        XCTAssertTrue(try ledger.beginReferenceMigration(token))

        let admission = SumiStartupAdmission.evaluate(
            preflight: .ready,
            profileReferenceAdmission: ledger,
            importJournal: SumiImportTransactionDatabaseJournal(
                database: database
            )
        )

        guard case .recoveryRequired = admission else {
            return XCTFail(
                "An interrupted profile deletion must retain emergency recovery chrome"
            )
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

    private func persistProfiles(
        _ profiles: [Profile],
        in database: SumiDatabase
    ) throws {
        try database.transaction {
            for (index, profile) in profiles.enumerated() {
                try $0.profiles.save(
                    ProfileRecord(
                        id: profile.id,
                        name: profile.name,
                        index: index
                    )
                )
            }
        }
    }

    private func persistRetiredTombstone(
        for profile: Profile,
        fallbackID: UUID,
        in database: SumiDatabase
    ) throws {
        let ledger = try ProfileReferenceAdmissionLedger(database: database)
        let token = try ledger.reserve(
            profile: profile,
            fallbackID: fallbackID
        )
        XCTAssertTrue(try ledger.beginReferenceMigration(token))
        XCTAssertTrue(try ledger.commitLogicalDeletion(token))
        XCTAssertTrue(try ledger.beginCleaning(token))
        for step in ProfileRetirementCleanupStep.ordered {
            XCTAssertTrue(try ledger.completeCleanupStep(step, using: token))
        }
        XCTAssertTrue(try ledger.markRetired(token))
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
