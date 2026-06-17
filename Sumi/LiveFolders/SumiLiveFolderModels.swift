import Foundation

enum SumiLiveFolderKind: String, Codable, CaseIterable, Sendable {
    case rss
    case githubPullRequests
    case githubIssues

    var defaultFolderName: String {
        switch self {
        case .rss:
            return "Live Feed"
        case .githubPullRequests:
            return "GitHub Pull Requests"
        case .githubIssues:
            return "GitHub Issues"
        }
    }

    var defaultURLString: String {
        switch self {
        case .rss:
            return ""
        case .githubPullRequests:
            return "https://github.com/pulls"
        case .githubIssues:
            return "https://github.com/issues/assigned"
        }
    }
}

enum SumiLiveFolderErrorKind: String, Codable, Sendable {
    case invalidURL
    case network
    case notAuthenticated
    case rateLimited
    case oversizedResponse
    case unsupportedResponse
    case parseFailed
    case noGitHubFilters

    var displayTitle: String {
        switch self {
        case .invalidURL:
            return "Invalid source URL"
        case .network:
            return "Refresh failed"
        case .notAuthenticated:
            return "Sign in required"
        case .rateLimited:
            return "Rate limited"
        case .oversizedResponse:
            return "Response too large"
        case .unsupportedResponse:
            return "Unsupported response"
        case .parseFailed:
            return "Could not read source"
        case .noGitHubFilters:
            return "No GitHub filters enabled"
        }
    }
}

struct SumiGitHubLiveFolderFilters: Codable, Equatable, Sendable {
    var authorMe = false
    var assignedMe = true
    var reviewRequested = false
}

struct SumiLiveFolderSource: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var folderId: UUID
    var spaceId: UUID
    var profileId: UUID?
    var kind: SumiLiveFolderKind
    var title: String
    var urlString: String
    var refreshIntervalSeconds: TimeInterval
    var maxItems: Int
    var timeRangeSeconds: TimeInterval?
    var githubFilters: SumiGitHubLiveFolderFilters
    var excludedRepositories: Set<String>
    var activeRepositories: Set<String>
    var etag: String?
    var lastModified: String?
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var nextRefreshAfter: Date?
    var consecutiveFailures: Int
    var lastErrorKind: SumiLiveFolderErrorKind?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        folderId: UUID,
        spaceId: UUID,
        profileId: UUID?,
        kind: SumiLiveFolderKind,
        title: String? = nil,
        urlString: String? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.spaceId = spaceId
        self.profileId = profileId
        self.kind = kind
        self.title = title ?? kind.defaultFolderName
        self.urlString = urlString ?? kind.defaultURLString
        self.refreshIntervalSeconds = 30 * 60
        self.maxItems = 10
        self.timeRangeSeconds = nil
        self.githubFilters = SumiGitHubLiveFolderFilters()
        self.excludedRepositories = []
        self.activeRepositories = []
        self.etag = nil
        self.lastModified = nil
        self.lastAttemptAt = nil
        self.lastSuccessAt = nil
        self.nextRefreshAfter = nil
        self.consecutiveFailures = 0
        self.lastErrorKind = nil
        self.isEnabled = true
    }

    var isDueForRefresh: Bool {
        guard isEnabled else { return false }
        guard let nextRefreshAfter else { return true }
        return nextRefreshAfter <= Date()
    }

    mutating func markAttempt(at date: Date = Date()) {
        lastAttemptAt = date
    }

    mutating func markSuccess(
        at date: Date = Date(),
        etag: String?,
        lastModified: String?
    ) {
        lastSuccessAt = date
        lastErrorKind = nil
        consecutiveFailures = 0
        self.etag = etag ?? self.etag
        self.lastModified = lastModified ?? self.lastModified
        nextRefreshAfter = date.addingTimeInterval(refreshIntervalSeconds)
    }

    mutating func markFailure(
        _ errorKind: SumiLiveFolderErrorKind,
        retryAfter: Date? = nil,
        at date: Date = Date()
    ) {
        lastErrorKind = errorKind
        consecutiveFailures += 1
        let backoff = min(pow(2, Double(max(0, consecutiveFailures - 1))) * 60, 30 * 60)
        nextRefreshAfter = retryAfter ?? date.addingTimeInterval(max(refreshIntervalSeconds, backoff))
    }
}

struct SumiLiveFolderItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var sourceId: UUID
    var title: String
    var urlString: String
    var subtitle: String?
    var publishedAt: Date?
    var updatedAt: Date?
    var sortDate: Date?
    var stateBadge: String?
    var iconSystemName: String?
    var firstSeenAt: Date
    var lastSeenAt: Date

    var sortKeyDate: Date {
        sortDate ?? updatedAt ?? publishedAt ?? firstSeenAt
    }

    var url: URL? {
        URL(string: urlString)
    }
}

struct SumiLiveFolderItemCache: Codable, Equatable, Sendable {
    var sourceId: UUID
    var items: [SumiLiveFolderItem]
}

struct SumiLiveFolderDismissalCache: Codable, Equatable, Sendable {
    var sourceId: UUID
    var itemIds: [String]
}

struct SumiLiveFolderDiskState: Codable, Equatable, Sendable {
    var sources: [SumiLiveFolderSource]
    var itemCaches: [SumiLiveFolderItemCache]
    var dismissals: [SumiLiveFolderDismissalCache]

    static let empty = SumiLiveFolderDiskState(
        sources: [],
        itemCaches: [],
        dismissals: []
    )
}

struct SumiLiveFolderProviderResponse: Sendable {
    enum Outcome: Sendable {
        case success(items: [SumiLiveFolderItem], title: String?, activeRepositories: Set<String>)
        case notModified
        case failure(SumiLiveFolderErrorKind, retryAfter: Date?)
    }

    var outcome: Outcome
    var etag: String?
    var lastModified: String?
}
