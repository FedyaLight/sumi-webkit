import Foundation
import SQLite3

/// Reads a source browser's SQLite database without touching the original file.
///
/// Source browsers are usually running while Sumi imports from them, so their
/// databases are in WAL mode with committed rows still sitting in the `-wal`
/// sidecar. Copying only the main database file does not merely miss recent
/// rows — until the first checkpoint the main file can hold no user tables at
/// all, so the import reads an empty database and reports success. The snapshot
/// therefore copies the `-wal` alongside it and opens the copy read-only, which
/// makes SQLite replay the log.
///
/// Two things are deliberately not done. `-shm` is not copied: it is a
/// rebuildable index into the WAL, and a snapshot taken while the browser
/// writes can disagree with the `-wal` beside it. And `immutable=1` is never
/// used: it tells SQLite to assume there is no WAL, which silently resurrects
/// the empty-database failure this type exists to prevent.
enum SumiImportSQLiteSnapshotReader {
    private static let sidecarSuffixes = ["-wal"]

    enum SnapshotError: LocalizedError {
        case missingDatabase(URL)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case let .missingDatabase(url):
                return "The database \(url.lastPathComponent) was not found."
            case let .unreadable(detail):
                return "Sumi could not open the source database: \(detail)"
            }
        }
    }

    /// Copies `databaseURL` and its WAL sidecars into `stagingDirectory`, opens
    /// the copy read-only, and hands the handle to `body`. The copy and the
    /// handle are both torn down before returning.
    static func withSnapshot<T>(
        of databaseURL: URL,
        in stagingDirectory: URL? = nil,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw SnapshotError.missingDatabase(databaseURL)
        }

        let root = stagingDirectory ?? fileManager.temporaryDirectory
        let snapshotDirectory = root.appendingPathComponent(
            "SumiImportSnapshot-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: snapshotDirectory) }

        let snapshotURL = snapshotDirectory.appendingPathComponent(databaseURL.lastPathComponent)
        try fileManager.copyItem(at: databaseURL, to: snapshotURL)
        for suffix in sidecarSuffixes {
            let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: sidecar.path) else { continue }
            // A sidecar that vanishes mid-copy (the browser checkpointed) is not
            // fatal: its contents are already in the main file we copied.
            try? fileManager.copyItem(
                at: sidecar,
                to: URL(fileURLWithPath: snapshotURL.path + suffix)
            )
        }

        guard let database = open(snapshotURL.path) else {
            throw SnapshotError.unreadable(databaseURL.lastPathComponent)
        }
        defer { sqlite3_close(database) }
        return try body(database)
    }

    /// Steps `sql` and yields each row to `row`. Callers read columns with the
    /// `column*` helpers below.
    static func query(
        _ database: OpaquePointer,
        _ sql: String,
        row: (OpaquePointer) throws -> Void
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(database))
            throw SnapshotError.unreadable(message)
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            try row(statement)
        }
    }

    static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: raw)
    }

    static func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    static func columnBlob(_ statement: OpaquePointer, _ index: Int32) -> Data? {
        guard let raw = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0 else { return nil }
        return Data(bytes: raw, count: count)
    }

    /// True when the database declares the given table, so callers can degrade
    /// on schema drift instead of throwing.
    static func hasTable(_ database: OpaquePointer, named table: String) -> Bool {
        var found = false
        let escaped = table.replacingOccurrences(of: "'", with: "''")
        try? query(
            database,
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(escaped)' LIMIT 1"
        ) { _ in
            found = true
        }
        return found
    }

    private static func open(_ path: String) -> OpaquePointer? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return nil
        }
        return database
    }
}
