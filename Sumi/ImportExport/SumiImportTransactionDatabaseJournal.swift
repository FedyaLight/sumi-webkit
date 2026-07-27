import Foundation

struct SumiImportTransactionDatabaseJournal:
    SumiImportTransactionJournal,
    Sendable
{
    private static let documentKey = "import.transaction"
    private let database: SumiDatabase

    init(database: SumiDatabase) {
        self.database = database
    }

    func load() async throws -> SumiImportTransactionJournalRecord? {
        try database.read { connection in
            guard let data = try connection.documents.data(
                forKey: Self.documentKey
            ) else {
                return nil
            }
            let record = try JSONDecoder().decode(
                SumiImportTransactionJournalRecord.self,
                from: data
            )
            guard record.version == SumiImportTransactionJournalRecord
                .currentVersion else {
                throw SumiImportTransactionJournalError.unsupportedVersion(
                    record.version
                )
            }
            return record
        }
    }

    func save(_ record: SumiImportTransactionJournalRecord) async throws {
        let data = try JSONEncoder().encode(record)
        try database.transaction { connection in
            if let currentData = try connection.documents.data(
                forKey: Self.documentKey
            ) {
                let current = try JSONDecoder().decode(
                    SumiImportTransactionJournalRecord.self,
                    from: currentData
                )
                guard current.phase.canTransition(to: record.phase) else {
                    throw SumiImportTransactionJournalError.invalidTransition(
                        from: current.phase,
                        to: record.phase
                    )
                }
            } else if record.phase != .prepared {
                throw SumiImportTransactionJournalError.invalidTransition(
                    from: .completed,
                    to: record.phase
                )
            }
            try connection.documents.save(data, forKey: Self.documentKey)
        }
    }

    func clear() async throws {
        try database.transaction { connection in
            guard let data = try connection.documents.data(
                forKey: Self.documentKey
            ) else {
                return
            }
            let record = try JSONDecoder().decode(
                SumiImportTransactionJournalRecord.self,
                from: data
            )
            guard record.phase == .completed else {
                throw SumiImportTransactionJournalError
                    .refusingToClearUncompleted(record.phase)
            }
            try connection.documents.delete(key: Self.documentKey)
        }
    }
}
