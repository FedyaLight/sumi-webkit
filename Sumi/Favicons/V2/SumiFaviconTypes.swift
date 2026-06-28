import AppKit
import Foundation

struct SumiFaviconPartition: Hashable, Codable, Sendable {
    let profileIdentifier: String
    let isPrivate: Bool

    init(profileIdentifier: String?, isPrivate: Bool) {
        let normalized = profileIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let normalized, !normalized.isEmpty {
            self.profileIdentifier = normalized
        } else {
            self.profileIdentifier = "default"
        }
        self.isPrivate = isPrivate
    }

    static func regular(_ profileID: UUID?) -> SumiFaviconPartition {
        SumiFaviconPartition(profileIdentifier: profileID?.uuidString, isPrivate: false)
    }

    static func privateEphemeral(_ profileID: UUID?) -> SumiFaviconPartition {
        SumiFaviconPartition(profileIdentifier: profileID?.uuidString, isPrivate: true)
    }

    var storageComponent: String {
        "\(isPrivate ? "private" : "profile")-\(profileIdentifier)"
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}

enum SumiFaviconCanonicalURL {
    static func pageURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: false) else {
            return url.absoluteURL
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil

        if components.scheme == "http" || components.scheme == "https" {
            if components.path.isEmpty {
                components.path = "/"
            }
            if (components.scheme == "https" && components.port == 443)
                || (components.scheme == "http" && components.port == 80) {
                components.port = nil
            }
        }

        return components.url ?? url.absoluteURL
    }

    static func pageKey(for url: URL) -> String {
        pageURL(url).absoluteString.lowercased()
    }

    static func siteKey(for url: URL) -> String? {
        let normalized = pageURL(url)
        guard let scheme = normalized.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = normalized.host?.lowercased()
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = normalized.port
        components.path = "/"
        return components.url?.absoluteString.lowercased()
    }

    static func candidateKey(for url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return url.absoluteString.lowercased()
        }
        return pageKey(for: url)
    }

    static func equivalentPageURLs(_ lhs: URL, _ rhs: URL) -> Bool {
        pageKey(for: lhs) == pageKey(for: rhs)
    }
}

enum SumiFaviconSourceKind: String, Codable, Sendable {
    case documentLink
    case extensionManifest
    case webAppManifest
    case rootFavicon
    case appleTouchRoot
    case browserFallback

    var discoveryRank: Int {
        switch self {
        case .documentLink:
            return 0
        case .extensionManifest:
            return 1
        case .webAppManifest:
            return 2
        case .rootFavicon:
            return 3
        case .appleTouchRoot:
            return 4
        case .browserFallback:
            return 5
        }
    }
}

enum SumiFaviconPurpose: String, Codable, Sendable {
    case any
    case maskable
    case monochrome
}

struct SumiFaviconDeclaredSize: Hashable, Codable, Sendable {
    let width: Int
    let height: Int

    var longestSide: Int {
        max(width, height)
    }
}

struct SumiFaviconCandidate: Hashable, Codable, Sendable {
    let pageURL: URL
    let iconURL: URL
    let sourceKind: SumiFaviconSourceKind
    let relTokens: [String]
    let declaredSizes: [SumiFaviconDeclaredSize]
    let declaredType: String?
    let purposes: [SumiFaviconPurpose]
    let media: String?
    let sourcePriority: Int
    let discoveredAt: Date
    let partition: SumiFaviconPartition

    init(
        pageURL: URL,
        iconURL: URL,
        sourceKind: SumiFaviconSourceKind,
        relTokens: [String] = [],
        declaredSizes: [SumiFaviconDeclaredSize] = [],
        declaredType: String? = nil,
        purposes: [SumiFaviconPurpose] = [.any],
        media: String? = nil,
        sourcePriority: Int? = nil,
        discoveredAt: Date = Date(),
        partition: SumiFaviconPartition
    ) {
        self.pageURL = pageURL
        self.iconURL = iconURL
        self.sourceKind = sourceKind
        self.relTokens = relTokens
        self.declaredSizes = declaredSizes
        self.declaredType = declaredType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.purposes = purposes.isEmpty ? [.any] : purposes
        self.media = media
        self.sourcePriority = sourcePriority ?? sourceKind.discoveryRank
        self.discoveredAt = discoveredAt
        self.partition = partition
    }
}

enum SumiFaviconFetchPriority: Int, Codable, Comparable, Sendable {
    case staleRefresh = 0
    case backgroundPrefetch = 1
    case historyBookmarkVisibleRow = 2
    case pinnedLauncher = 3
    case visibleSidebarOrTabStrip = 4
    case visibleActiveTab = 5

    static func < (lhs: SumiFaviconFetchPriority, rhs: SumiFaviconFetchPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum SumiFaviconDisplayContext: String, Codable, Sendable {
    case menu
    case tabSidebar
    case historyBookmarkRow
    case pinnedLauncher
    case largePreview

    var canonicalPointSize: CGFloat {
        switch self {
        case .menu:
            return 16
        case .tabSidebar:
            return 18
        case .historyBookmarkRow:
            return 22
        case .pinnedLauncher:
            return 20
        case .largePreview:
            return 64
        }
    }

    var canonicalCornerRadius: CGFloat {
        switch self {
        case .menu:
            return 4
        case .tabSidebar:
            return 6
        case .historyBookmarkRow:
            return 6
        case .pinnedLauncher:
            return 6
        case .largePreview:
            return 12
        }
    }
}

enum SumiFaviconTemplateMode: Hashable, Codable, Sendable {
    case original
    case template
}

struct SumiPreparedFaviconRequest: Hashable, Sendable {
    let pageURL: URL
    let partition: SumiFaviconPartition
    let context: SumiFaviconDisplayContext
    let backingScale: CGFloat
    let templateMode: SumiFaviconTemplateMode
    let appearanceName: String?

    init(
        pageURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext,
        backingScale: CGFloat,
        templateMode: SumiFaviconTemplateMode = .original,
        appearanceName: String? = nil
    ) {
        self.pageURL = pageURL
        self.partition = partition
        self.context = context
        self.backingScale = max(1, backingScale.rounded())
        self.templateMode = templateMode
        self.appearanceName = appearanceName
    }

    var pointSize: CGFloat {
        context.canonicalPointSize
    }

    var pixelSize: Int {
        max(1, Int((context.canonicalPointSize * backingScale).rounded(.up)))
    }

    var cornerRadius: CGFloat {
        context.canonicalCornerRadius
    }
}

struct SumiPreparedFaviconIdentity: Hashable, Sendable {
    let partition: SumiFaviconPartition
    let blobID: String
    let revision: String
    let sourceURL: URL
    let request: SumiPreparedFaviconRequest
}

enum SumiFaviconPayloadKind: String, Codable, Sendable {
    case png
    case jpeg
    case gif
    case webp
    case ico
    case svg
    case unknownRaster

    var preferredFileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        case .gif:
            return "gif"
        case .webp:
            return "webp"
        case .ico:
            return "ico"
        case .svg:
            return "svg"
        case .unknownRaster:
            return "img"
        }
    }
}

enum SumiFaviconValidationFailureKind: String, Codable, Sendable {
    case transport
    case notFound
    case invalidPayload
    case oversizedPayload
    case oversizedPixels
    case htmlPayload
    case unsafeSVG
    case unsupported
    case noIconFound
}

struct SumiFaviconValidatedPayload: Sendable {
    let data: Data
    let payloadKind: SumiFaviconPayloadKind
    let mimeType: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let byteCount: Int
}

enum SumiFaviconValidationResult: Sendable {
    case valid(SumiFaviconValidatedPayload)
    case invalid(SumiFaviconValidationFailureKind)
}

enum SumiFaviconTTL {
    static let positive: TimeInterval = 60 * 60 * 24 * 30
    static let transientTransportFailure: TimeInterval = 60 * 10
    static let verifiedInvalidPayload: TimeInterval = 60 * 60 * 6
    static let noIconFound: TimeInterval = 60 * 60 * 24
}

enum SumiFaviconConstants {
    static let maxPayloadBytes = 1024 * 1024
    static let maxSVGPayloadBytes = 384 * 1024
    static let maxRasterPixels = 1024 * 1024
    static let maxDecodedMasterPixelSize = 256
    static let preparedMemoryBudgetBytes = 12 * 1024 * 1024
    static let diskBudgetBytes = 64 * 1024 * 1024
}
