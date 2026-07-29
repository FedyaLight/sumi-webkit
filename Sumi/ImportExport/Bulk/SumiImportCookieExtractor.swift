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
    var allowedSourceProfileKeys: Set<String>?
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
            let outcome = try firefoxCookies()
            cookies = outcome.cookies
            skipped = outcome.skipped
            reasons = outcome.reasons
        case .safari:
            cookies = try safariCookies()
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
        var appBoundSkipped = 0

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
                        if error == .appBoundEncryption {
                            appBoundSkipped += 1
                        }
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
        if appBoundSkipped > 0 {
            reasons.append(
                "Some cookies are locked to the browser that created them and could not be imported."
            )
        }
        if skipped > appBoundSkipped {
            reasons.append(
                "Some encrypted cookies could not be decrypted with the source browser's Safe Storage key."
            )
        }
        return (cookies, skipped, reasons)
    }

    private func firefoxCookies() throws -> (
        cookies: [SumiStagedCookie],
        skipped: Int,
        reasons: [String]
    ) {
        try SumiImportSQLiteSnapshotReader.withSnapshot(
            of: profileURL.appendingPathComponent("cookies.sqlite")
        ) { database in
            guard SumiImportSQLiteSnapshotReader.hasTable(
                database,
                named: "moz_cookies"
            ) else {
                return ([], 0, [])
            }
            var cookies: [SumiStagedCookie] = []
            var skippedPartitioned = 0
            try SumiImportSQLiteSnapshotReader.query(
                database,
                """
                SELECT host, name, value, path, expiry, isSecure, isHttpOnly, originAttributes
                FROM moz_cookies
                """
            ) { statement in
                guard let host = SumiImportSQLiteSnapshotReader.columnText(statement, 0),
                      let name = SumiImportSQLiteSnapshotReader.columnText(statement, 1)
                else { return }
                let originAttributes = SumiImportSQLiteSnapshotReader.columnText(statement, 7) ?? ""
                guard originAttributes.contains("partitionKey=") == false else {
                    skippedPartitioned += 1
                    return
                }
                let userContextId = SumiMozillaCookiePartition.userContextId(
                    from: originAttributes
                )
                let sourceProfileKey = SumiMozillaCookiePartition
                    .sourceProfileKey(
                        directoryName: profileURL.lastPathComponent,
                        userContextId: userContextId
                    )
                if let allowedSourceProfileKeys,
                   allowedSourceProfileKeys.contains(sourceProfileKey) == false {
                    return
                }
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
                        isHTTPOnly: SumiImportSQLiteSnapshotReader.columnInt(statement, 6) != 0,
                        sourceProfileKey: sourceProfileKey
                    )
                )
            }
            let reasons = skippedPartitioned > 0
                ? [
                    "Partitioned Mozilla cookies cannot be represented by WebKit and were skipped.",
                ]
                : []
            return (cookies, skippedPartitioned, reasons)
        }
    }

    private func safariCookies() throws -> [SumiStagedCookie] {
        let libraryURL = profileURL.deletingLastPathComponent()
        let candidates = [
            libraryURL.appendingPathComponent(
                "Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
            ),
            libraryURL.appendingPathComponent("Cookies/Cookies.binarycookies"),
        ]
        guard let source = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            return []
        }
        return try SumiSafariBinaryCookiesParser.parse(Data(contentsOf: source))
    }
}

enum SumiSafariBinaryCookiesParser {
    private static let cocoaEpoch = Date(timeIntervalSince1970: 978_307_200)

    static func parse(_ data: Data) throws -> [SumiStagedCookie] {
        guard data.count >= 8, data.prefix(4) == Data("cook".utf8) else {
            throw SumiImportExportError.unsupportedFile(
                "Safari Cookies.binarycookies has an invalid header."
            )
        }
        let pageCount = try int32(data, at: 4, bigEndian: true)
        let sizeTableEnd = 8 + pageCount * 4
        guard pageCount >= 0, sizeTableEnd <= data.count else {
            throw SumiImportExportError.unsupportedFile(
                "Safari Cookies.binarycookies has a truncated page table."
            )
        }

        var cursor = sizeTableEnd
        var output: [SumiStagedCookie] = []
        for pageIndex in 0..<pageCount {
            let pageSize = try int32(data, at: 8 + pageIndex * 4, bigEndian: true)
            guard pageSize >= 0, cursor + pageSize <= data.count else {
                throw SumiImportExportError.unsupportedFile(
                    "Safari Cookies.binarycookies has a truncated page."
                )
            }
            output.append(contentsOf: try parsePage(data.subdata(in: cursor..<(cursor + pageSize))))
            cursor += pageSize
        }
        return output
    }

    private static func parsePage(_ page: Data) throws -> [SumiStagedCookie] {
        guard page.count >= 8, page.prefix(4) == Data([0, 0, 1, 0]) else {
            throw SumiImportExportError.unsupportedFile(
                "Safari Cookies.binarycookies has an invalid page header."
            )
        }
        let count = try int32(page, at: 4)
        guard count >= 0, 8 + count * 4 <= page.count else {
            throw SumiImportExportError.unsupportedFile(
                "Safari Cookies.binarycookies has a truncated cookie table."
            )
        }
        return try (0..<count).map { index in
            try parseCookie(page, at: int32(page, at: 8 + index * 4))
        }
    }

    private static func parseCookie(_ page: Data, at offset: Int) throws -> SumiStagedCookie {
        guard offset >= 0, offset + 56 <= page.count else {
            throw SumiImportExportError.unsupportedFile(
                "Safari Cookies.binarycookies has a truncated cookie record."
            )
        }
        let size = try int32(page, at: offset)
        guard size >= 56, offset + size <= page.count else {
            throw SumiImportExportError.unsupportedFile(
                "Safari Cookies.binarycookies has an invalid cookie size."
            )
        }
        let flags = try int32(page, at: offset + 8)
        let domain = try string(page, recordOffset: offset, relativeOffsetAt: offset + 16, size: size)
        let name = try string(page, recordOffset: offset, relativeOffsetAt: offset + 20, size: size)
        let path = try string(page, recordOffset: offset, relativeOffsetAt: offset + 24, size: size)
        let value = try string(page, recordOffset: offset, relativeOffsetAt: offset + 28, size: size)
        let expiry = try double(page, at: offset + 40)
        return SumiStagedCookie(
            name: name,
            value: value,
            domain: domain,
            path: path.isEmpty ? "/" : path,
            expiresAt: expiry > 0 ? cocoaEpoch.addingTimeInterval(expiry) : nil,
            isSecure: flags & 0x1 != 0,
            isHTTPOnly: flags & 0x4 != 0
        )
    }

    private static func string(
        _ data: Data,
        recordOffset: Int,
        relativeOffsetAt: Int,
        size: Int
    ) throws -> String {
        let start = recordOffset + (try int32(data, at: relativeOffsetAt))
        let endLimit = recordOffset + size
        guard start >= recordOffset, start < endLimit else {
            throw SumiImportExportError.unsupportedFile(
                "Safari Cookies.binarycookies has an invalid string offset."
            )
        }
        let end = data[start..<endLimit].firstIndex(of: 0) ?? endLimit
        return String(decoding: data[start..<end], as: UTF8.self)
    }

    private static func int32(
        _ data: Data,
        at offset: Int,
        bigEndian: Bool = false
    ) throws -> Int {
        guard offset >= 0, offset + 4 <= data.count else {
            throw SumiImportExportError.unsupportedFile(
                "Safari Cookies.binarycookies is truncated."
            )
        }
        let bytes = data[offset..<(offset + 4)]
        let value = bigEndian
            ? bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            : bytes.enumerated().reduce(UInt32(0)) {
                $0 | (UInt32($1.element) << UInt32($1.offset * 8))
            }
        return Int(value)
    }

    private static func double(_ data: Data, at offset: Int) throws -> Double {
        guard offset >= 0, offset + 8 <= data.count else {
            throw SumiImportExportError.unsupportedFile(
                "Safari Cookies.binarycookies is truncated."
            )
        }
        let bits = data[offset..<(offset + 8)].enumerated().reduce(UInt64(0)) {
            $0 | (UInt64($1.element) << UInt64($1.offset * 8))
        }
        return Double(bitPattern: bits)
    }
}
