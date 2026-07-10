import Foundation

struct SumiStoredFaviconSelection: Sendable {
    let partition: SumiFaviconPartition
    let pageURL: URL
    let sourceURL: URL
    let blobID: String
    let revision: String
    let payloadKind: SumiFaviconPayloadKind
    let mimeType: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let sourceKind: SumiFaviconSourceKind
    let declaredSizes: [SumiFaviconDeclaredSize]
    let declaredType: String?
    let purposes: [SumiFaviconPurpose]
    let updatedAt: Date
}

struct SumiFaviconInvalidation: Hashable, Sendable {
    let partition: SumiFaviconPartition
    let revision: String
}

struct SumiFaviconAliasAssociationResult: Sendable {
    let invalidations: [SumiFaviconInvalidation]
    let didChange: Bool

    static let empty = SumiFaviconAliasAssociationResult(invalidations: [], didChange: false)
}

struct SumiFaviconBlobMetadata: Codable {
    static let currentSchemaVersion = 2

    var schemaVersion = currentSchemaVersion
    var blobs: [String: SumiFaviconBlobRecord] = [:]
    var pageMappings: [String: SumiFaviconPageMapping] = [:]
    var pageAliases: [String: String] = [:]
    var candidateMappings: [String: SumiFaviconCandidateRecord] = [:]
    var noIconUntilBySiteKey: [String: Date] = [:]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case blobs
        case pageMappings
        case pageAliases
        case candidateMappings
        case noIconUntilBySiteKey
    }

    init() { /* Uses property defaults for an empty metadata index. */ }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        blobs = try container.decodeIfPresent(
            [String: SumiFaviconBlobRecord].self,
            forKey: .blobs
        ) ?? [:]
        pageMappings = try container.decodeIfPresent(
            [String: SumiFaviconPageMapping].self,
            forKey: .pageMappings
        ) ?? [:]
        pageAliases = try container.decodeIfPresent(
            [String: String].self,
            forKey: .pageAliases
        ) ?? [:]
        candidateMappings = try container.decodeIfPresent(
            [String: SumiFaviconCandidateRecord].self,
            forKey: .candidateMappings
        ) ?? [:]
        noIconUntilBySiteKey = try container.decodeIfPresent(
            [String: Date].self,
            forKey: .noIconUntilBySiteKey
        ) ?? [:]
    }
}

struct SumiFaviconBlobRecord: Codable {
    let blobID: String
    let revision: String
    let payloadKind: SumiFaviconPayloadKind
    let mimeType: String?
    let byteCount: Int
    let pixelWidth: Int?
    let pixelHeight: Int?
    var createdAt: Date
    var lastAccessedAt: Date
    let fileName: String
}

struct SumiFaviconPageMapping: Codable {
    let pageKey: String
    let siteKey: String?
    let pageURL: URL
    let sourceURL: URL
    let blobID: String
    let revision: String
    let sourceKind: SumiFaviconSourceKind
    let declaredSizes: [SumiFaviconDeclaredSize]
    let declaredType: String?
    let purposes: [SumiFaviconPurpose]
    let updatedAt: Date
    let expiresAt: Date
}

struct SumiFaviconCandidateRecord: Codable {
    let candidateURL: URL
    var blobID: String?
    var revision: String?
    var sourceKind: SumiFaviconSourceKind?
    var lastFetchAt: Date
    var positiveUntil: Date?
    var negativeUntil: Date?
    var failureKind: SumiFaviconValidationFailureKind?
}

struct SumiFaviconAliasWriteResult {
    let invalidations: [SumiFaviconInvalidation]
    let didChange: Bool

    static let empty = SumiFaviconAliasWriteResult(invalidations: [], didChange: false)
}

struct SumiFaviconBlobIdentity {
    let blobID: String
    let fileName: String
}
