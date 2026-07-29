import Foundation
import SQLite3

/// Reads browsing history out of a source browser and stages it as NDJSON.
///
/// Every source is read through `SumiImportSQLiteSnapshotReader`, so a running
/// browser's uncheckpointed rows are included and its live database is never
/// opened.
struct SumiImportHistoryExtractor {
    struct Extraction {
        var recordCount: Int
        var byteCount: Int
        var skipped: Int
        var skipReasons: [String]
    }

    /// A ceiling on how much history a single import will carry. Beyond this
    /// the newest visits are kept: a user with a decade of history wants their
    /// recent past, not a multi-hour import.
    static let maximumVisits = 200_000

    var family: SumiBrowserFamily
    var profileURL: URL

    func stage(to fileURL: URL, staging: SumiImportBulkStagingStore) throws -> Extraction {
        var seen = 0
        let written = try staging.writeStream(to: fileURL) { emit in
            try readVisits { visit in
                seen += 1
                if seen.isMultiple(of: 256) {
                    try Task.checkCancellation()
                }
                guard seen <= Self.maximumVisits else { return }
                try emit(visit)
            }
        }
        let skipped = max(seen - written.count, 0)
        return Extraction(
            recordCount: written.count,
            byteCount: written.bytes,
            skipped: skipped,
            skipReasons: skipped > 0
                ? ["Only the \(Self.maximumVisits.formatted()) most recent visits were imported."]
                : []
        )
    }

    // MARK: - Per-family readers

    private func readVisits(
        _ visit: (SumiStagedHistoryVisit) throws -> Void
    ) throws {
        switch family {
        case .chromium, .arc:
            try chromiumVisits(visit)
        case .firefox, .zen:
            try firefoxVisits(visit)
        case .safari:
            try safariVisits(visit)
        }
    }

    private func chromiumVisits(
        _ visit: (SumiStagedHistoryVisit) throws -> Void
    ) throws {
        try SumiImportSQLiteSnapshotReader.withSnapshot(
            of: profileURL.appendingPathComponent("History")
        ) { database in
            guard SumiImportSQLiteSnapshotReader.hasTable(database, named: "visits") else { return }
            try SumiImportSQLiteSnapshotReader.query(
                database,
                """
                SELECT urls.url, urls.title, visits.visit_time
                FROM visits JOIN urls ON urls.id = visits.url
                WHERE urls.url LIKE 'http%'
                ORDER BY visits.visit_time DESC
                """
            ) { statement in
                guard let url = SumiImportSQLiteSnapshotReader.columnText(statement, 0),
                      let date = SumiBrowserEpochs.chromium(
                          microseconds: SumiImportSQLiteSnapshotReader.columnInt(statement, 2)
                      )
                else { return }
                try visit(
                    SumiStagedHistoryVisit(
                        urlString: url,
                        title: SumiImportSQLiteSnapshotReader.columnText(statement, 1) ?? "",
                        visitedAt: date
                    )
                )
            }
        }
    }

    private func firefoxVisits(
        _ visit: (SumiStagedHistoryVisit) throws -> Void
    ) throws {
        try SumiImportSQLiteSnapshotReader.withSnapshot(
            of: profileURL.appendingPathComponent("places.sqlite")
        ) { database in
            guard SumiImportSQLiteSnapshotReader.hasTable(database, named: "moz_historyvisits") else { return }
            try SumiImportSQLiteSnapshotReader.query(
                database,
                """
                SELECT moz_places.url, moz_places.title, moz_historyvisits.visit_date
                FROM moz_historyvisits JOIN moz_places ON moz_places.id = moz_historyvisits.place_id
                WHERE moz_places.url LIKE 'http%'
                ORDER BY moz_historyvisits.visit_date DESC
                """
            ) { statement in
                guard let url = SumiImportSQLiteSnapshotReader.columnText(statement, 0),
                      let date = SumiBrowserEpochs.firefox(
                          microseconds: SumiImportSQLiteSnapshotReader.columnInt(statement, 2)
                      )
                else { return }
                try visit(
                    SumiStagedHistoryVisit(
                        urlString: url,
                        title: SumiImportSQLiteSnapshotReader.columnText(statement, 1) ?? "",
                        visitedAt: date
                    )
                )
            }
        }
    }

    private func safariVisits(
        _ visit: (SumiStagedHistoryVisit) throws -> Void
    ) throws {
        try SumiImportSQLiteSnapshotReader.withSnapshot(
            of: profileURL.appendingPathComponent("History.db")
        ) { database in
            guard SumiImportSQLiteSnapshotReader.hasTable(database, named: "history_visits") else { return }
            try SumiImportSQLiteSnapshotReader.query(
                database,
                """
                SELECT history_items.url, history_visits.title, history_visits.visit_time
                FROM history_visits JOIN history_items ON history_items.id = history_visits.history_item
                WHERE history_items.url LIKE 'http%'
                ORDER BY history_visits.visit_time DESC
                """
            ) { statement in
                guard let url = SumiImportSQLiteSnapshotReader.columnText(statement, 0),
                      let date = SumiBrowserEpochs.safari(
                          absoluteSeconds: sqlite3_column_double(statement, 2)
                      )
                else { return }
                try visit(
                    SumiStagedHistoryVisit(
                        urlString: url,
                        title: SumiImportSQLiteSnapshotReader.columnText(statement, 1) ?? "",
                        visitedAt: date
                    )
                )
            }
        }
    }
}
