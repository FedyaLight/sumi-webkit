import Foundation
import SQLite3

/// Stages cookies so imported sessions stay signed in.
///
/// Chromium encrypts its cookie values with a key held in the login keychain
/// under an access control that names only the source browser, so macOS asks
/// the user to authorize the read. A refusal, or a browser using app-bound
/// encryption, skips cookies with a counted reason rather than failing.
struct SumiImportCookieExtractor {
    struct Extraction {
        var recordCount: Int
        var byteCount: Int
        var skipped: Int
        var skipReasons: [String]
    }

    var family: SumiBrowserFamily
    var profileURL: URL
    /// Keychain service/account for the source browser, e.g. ("Chrome Safe
    /// Storage", "Chrome"). Absent for Firefox, which stores cookies in clear.
    var safeStorage: (service: String, account: String)?
    var decryptor = SumiChromiumSafeStorageDecryptor()

    func stage(to fileURL: URL, staging: SumiImportBulkStagingStore) throws -> Extraction {
        var skipped = 0
        var reasons: [String] = []
        let cookies: [SumiStagedCookie]

        switch family {
        case .chromium, .arc:
            let outcome = try chromiumCookies()
            cookies = outcome.cookies
            skipped = outcome.skipped
            reasons = outcome.reasons
        case .firefox, .zen:
            cookies = try firefoxCookies()
        case .safari:
            // Safari's `Cookies.binarycookies` lives inside a TCC-protected
            // container in an undocumented binary format.
            cookies = []
            reasons = ["Safari's cookies cannot be read by other apps, so signed-in sessions were not imported."]
        }

        let written = try staging.write(cookies, to: fileURL)
        return Extraction(
            recordCount: written.count,
            byteCount: written.bytes,
            skipped: skipped,
            skipReasons: reasons
        )
    }

    private func chromiumCookies() throws -> (cookies: [SumiStagedCookie], skipped: Int, reasons: [String]) {
        guard let cookiesURL = SumiChromiumProfileCatalogReader.cookiesURL(inProfile: profileURL) else {
            return ([], 0, [])
        }
        guard let safeStorage else { return ([], 0, []) }

        let key: [UInt8]
        switch decryptor.derivedKey(service: safeStorage.service, account: safeStorage.account) {
        case let .success(derived):
            key = derived
        case let .failure(error):
            return ([], 0, [error.localizedDescription])
        }

        var cookies: [SumiStagedCookie] = []
        var skipped = 0
        var appBound = false

        try SumiImportSQLiteSnapshotReader.withSnapshot(of: cookiesURL) { database in
            guard SumiImportSQLiteSnapshotReader.hasTable(database, named: "cookies") else { return }
            try SumiImportSQLiteSnapshotReader.query(
                database,
                """
                SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly
                FROM cookies
                """
            ) { statement in
                guard let host = SumiImportSQLiteSnapshotReader.columnText(statement, 0),
                      let name = SumiImportSQLiteSnapshotReader.columnText(statement, 1)
                else { return }

                let plain = SumiImportSQLiteSnapshotReader.columnText(statement, 2) ?? ""
                let value: String
                if plain.isEmpty, let blob = SumiImportSQLiteSnapshotReader.columnBlob(statement, 3) {
                    switch decryptor.decrypt(blob, key: key, host: host) {
                    case let .success(decrypted):
                        value = decrypted
                    case let .failure(error):
                        if error == .appBoundEncryption { appBound = true }
                        skipped += 1
                        return
                    }
                } else {
                    value = plain
                }

                cookies.append(
                    SumiStagedCookie(
                        name: name,
                        value: value,
                        domain: host,
                        path: SumiImportSQLiteSnapshotReader.columnText(statement, 4) ?? "/",
                        expiresAt: SumiBrowserEpochs.chromium(
                            microseconds: SumiImportSQLiteSnapshotReader.columnInt(statement, 5)
                        ),
                        isSecure: SumiImportSQLiteSnapshotReader.columnInt(statement, 6) != 0,
                        isHTTPOnly: SumiImportSQLiteSnapshotReader.columnInt(statement, 7) != 0
                    )
                )
            }
        }

        var reasons: [String] = []
        if appBound {
            reasons.append(
                "Some cookies are locked to the browser that created them and could not be imported."
            )
        }
        return (cookies, skipped, reasons)
    }

    private func firefoxCookies() throws -> [SumiStagedCookie] {
        try SumiImportSQLiteSnapshotReader.withSnapshot(
            of: profileURL.appendingPathComponent("cookies.sqlite")
        ) { database in
            guard SumiImportSQLiteSnapshotReader.hasTable(database, named: "moz_cookies") else { return [] }
            var cookies: [SumiStagedCookie] = []
            try SumiImportSQLiteSnapshotReader.query(
                database,
                "SELECT host, name, value, path, expiry, isSecure, isHttpOnly FROM moz_cookies"
            ) { statement in
                guard let host = SumiImportSQLiteSnapshotReader.columnText(statement, 0),
                      let name = SumiImportSQLiteSnapshotReader.columnText(statement, 1)
                else { return }
                cookies.append(
                    SumiStagedCookie(
                        name: name,
                        value: SumiImportSQLiteSnapshotReader.columnText(statement, 2) ?? "",
                        domain: host,
                        path: SumiImportSQLiteSnapshotReader.columnText(statement, 3) ?? "/",
                        expiresAt: SumiBrowserEpochs.firefoxCookieExpiry(
                            SumiImportSQLiteSnapshotReader.columnInt(statement, 4)
                        ),
                        isSecure: SumiImportSQLiteSnapshotReader.columnInt(statement, 5) != 0,
                        isHTTPOnly: SumiImportSQLiteSnapshotReader.columnInt(statement, 6) != 0
                    )
                )
            }
            return cookies
        }
    }
}
