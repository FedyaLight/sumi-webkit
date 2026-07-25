import Foundation

/// Data that is imported by volume rather than by structure.
///
/// These are deliberately *not* `SumiImportCategory` cases. Categories define
/// the scope of Sumi's logical backup format, and history, cookies, and
/// favicons are all excluded from backups by design. Folding them into that
/// enum would silently widen what a `.sumibackup` claims to contain.
enum SumiImportBulkKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case history
    case favicons
    case cookies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "History"
        case .favicons: return "Site icons"
        case .cookies: return "Signed-in sessions"
        }
    }

    /// Applied in order of increasing irreversibility, so a failure late in the
    /// sequence never demands an impossible rollback of something earlier.
    static let applyOrder: [SumiImportBulkKind] = [.history, .favicons, .cookies]
}

/// Describes payloads staged on disk during preview. Small, `Equatable`, and
/// `Codable`, so it is safe to carry through the plan and the durable journal
/// while the payloads themselves stay in files.
struct SumiImportBulkStagingManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    struct Entry: Codable, Equatable, Sendable {
        var kind: SumiImportBulkKind
        /// The source browser's profile directory, joined against
        /// `SumiPortableProfile.sourceDirectoryKey`.
        var sourceProfileKey: String
        var fileName: String
        var blobDirectoryName: String?
        var recordCount: Int
        var byteCount: Int
        var skipped: Int
        var skipReasons: [String]
    }

    var version: Int
    var stagingID: UUID
    var sourceKind: SumiImportSourceKind
    var entries: [Entry]

    init(
        version: Int = SumiImportBulkStagingManifest.currentVersion,
        stagingID: UUID,
        sourceKind: SumiImportSourceKind,
        entries: [Entry]
    ) {
        self.version = version
        self.stagingID = stagingID
        self.sourceKind = sourceKind
        self.entries = entries
    }

    var kinds: Set<SumiImportBulkKind> { Set(entries.map(\.kind)) }

    func recordCount(for kind: SumiImportBulkKind) -> Int {
        entries.filter { $0.kind == kind }.reduce(0) { $0 + $1.recordCount }
    }

    func skippedCount(for kind: SumiImportBulkKind) -> Int {
        entries.filter { $0.kind == kind }.reduce(0) { $0 + $1.skipped }
    }

    func skipReasons(for kind: SumiImportBulkKind) -> [String] {
        var seen: Set<String> = []
        return entries
            .filter { $0.kind == kind }
            .flatMap(\.skipReasons)
            .filter { seen.insert($0).inserted }
    }
}

struct SumiImportBulkProgress: Equatable, Sendable {
    var kind: SumiImportBulkKind
    var completed: Int
    var total: Int
}

// MARK: - Staged record shapes

/// One visited page. Times are absolute so every source browser's epoch is
/// normalised before staging rather than at apply time.
struct SumiStagedHistoryVisit: Codable, Equatable, Sendable {
    var urlString: String
    var title: String
    var visitedAt: Date
}

struct SumiStagedFavicon: Codable, Equatable, Sendable {
    var pageURLString: String
    var iconURLString: String
    var blobFileName: String
}

struct SumiStagedCookie: Codable, Equatable, Sendable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresAt: Date?
    var isSecure: Bool
    var isHTTPOnly: Bool

    /// Cookies are identified by the tuple browsers use for replacement.
    var identity: String { "\(name)\u{1}\(domain)\u{1}\(path)" }
}
