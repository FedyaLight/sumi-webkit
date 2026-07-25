import Foundation
import SQLite3

/// Stages site icons from a source browser so an imported sidebar shows real
/// icons immediately instead of a column of blank squares that fill in only as
/// the user visits each site again.
struct SumiImportFaviconExtractor {
    struct Extraction {
        var recordCount: Int
        var byteCount: Int
        var skipped: Int
        var skipReasons: [String]
    }

    /// Matches the favicon store's own ceiling; larger payloads would be
    /// rejected downstream anyway.
    static let maximumPayloadBytes = 1024 * 1024
    static let maximumIcons = 5_000

    var family: SumiBrowserFamily
    var profileURL: URL

    func stage(
        to fileURL: URL,
        blobDirectory: URL,
        staging: SumiImportBulkStagingStore
    ) throws -> Extraction {
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)

        var skipped = 0
        var reasons: [String] = []
        var records: [SumiStagedFavicon] = []

        let rows: [(page: String, icon: String, payload: Data)]
        switch family {
        case .chromium, .arc:
            rows = try chromiumIcons()
        case .firefox, .zen:
            rows = try firefoxIcons()
        case .safari:
            // Safari keeps its touch-icon cache in a private container format
            // with no stable schema; icons are re-fetched on first visit.
            rows = []
        }

        for row in rows.prefix(Self.maximumIcons) {
            guard row.payload.count <= Self.maximumPayloadBytes else {
                skipped += 1
                continue
            }
            let blobName = "\(records.count).icon"
            do {
                try row.payload.write(to: blobDirectory.appendingPathComponent(blobName))
            } catch {
                skipped += 1
                continue
            }
            records.append(
                SumiStagedFavicon(
                    pageURLString: row.page,
                    iconURLString: row.icon,
                    blobFileName: blobName
                )
            )
        }
        if rows.count > Self.maximumIcons {
            skipped += rows.count - Self.maximumIcons
            reasons.append("Only the \(Self.maximumIcons.formatted()) most-used site icons were imported.")
        }

        let written = try staging.write(records, to: fileURL)
        return Extraction(
            recordCount: written.count,
            byteCount: written.bytes,
            skipped: skipped,
            skipReasons: reasons
        )
    }

    private func chromiumIcons() throws -> [(page: String, icon: String, payload: Data)] {
        try SumiImportSQLiteSnapshotReader.withSnapshot(
            of: profileURL.appendingPathComponent("Favicons")
        ) { database in
            guard SumiImportSQLiteSnapshotReader.hasTable(database, named: "favicon_bitmaps") else { return [] }
            var output: [(String, String, Data)] = []
            // One bitmap per page: the largest, which is what a sidebar wants.
            try SumiImportSQLiteSnapshotReader.query(
                database,
                """
                SELECT icon_mapping.page_url, favicons.url, favicon_bitmaps.image_data
                FROM favicon_bitmaps
                JOIN favicons ON favicons.id = favicon_bitmaps.icon_id
                JOIN icon_mapping ON icon_mapping.icon_id = favicons.id
                WHERE favicon_bitmaps.image_data IS NOT NULL
                GROUP BY icon_mapping.page_url
                HAVING MAX(favicon_bitmaps.width)
                """
            ) { statement in
                guard let page = SumiImportSQLiteSnapshotReader.columnText(statement, 0),
                      let icon = SumiImportSQLiteSnapshotReader.columnText(statement, 1),
                      let payload = SumiImportSQLiteSnapshotReader.columnBlob(statement, 2)
                else { return }
                output.append((page, icon, payload))
            }
            return output
        }
    }

    private func firefoxIcons() throws -> [(page: String, icon: String, payload: Data)] {
        try SumiImportSQLiteSnapshotReader.withSnapshot(
            of: profileURL.appendingPathComponent("favicons.sqlite")
        ) { database in
            guard SumiImportSQLiteSnapshotReader.hasTable(database, named: "moz_icons") else { return [] }
            var output: [(String, String, Data)] = []
            try SumiImportSQLiteSnapshotReader.query(
                database,
                """
                SELECT moz_pages_w_icons.page_url, moz_icons.icon_url, moz_icons.data
                FROM moz_icons
                JOIN moz_icons_to_pages ON moz_icons_to_pages.icon_id = moz_icons.id
                JOIN moz_pages_w_icons ON moz_pages_w_icons.id = moz_icons_to_pages.page_id
                WHERE moz_icons.data IS NOT NULL
                GROUP BY moz_pages_w_icons.page_url
                HAVING MAX(moz_icons.width)
                """
            ) { statement in
                guard let page = SumiImportSQLiteSnapshotReader.columnText(statement, 0),
                      let icon = SumiImportSQLiteSnapshotReader.columnText(statement, 1),
                      let payload = SumiImportSQLiteSnapshotReader.columnBlob(statement, 2)
                else { return }
                output.append((page, icon, payload))
            }
            return output
        }
    }
}
