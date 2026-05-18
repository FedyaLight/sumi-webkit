import Foundation

enum AdblockCompiledRuleGroupKind: String, Codable, CaseIterable, Hashable, Sendable {
    case network
    case nativeCosmeticCSS
}

struct NativeContentBlockingCompilerIdentity: Codable, Equatable, Sendable {
    let name: String
    let version: String
}

struct NativeContentBlockingSourceList: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let contentHash: String
    let category: AdblockFilterListCategory?
    let inputByteCount: Int?
    let approximateRuleCount: Int?

    init(
        id: String,
        displayName: String,
        contentHash: String,
        category: AdblockFilterListCategory? = nil,
        inputByteCount: Int? = nil,
        approximateRuleCount: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.contentHash = contentHash
        self.category = category
        self.inputByteCount = inputByteCount
        self.approximateRuleCount = approximateRuleCount
    }
}

struct NativeContentBlockingRuleCapDiagnostics: Codable, Equatable, Sendable {
    struct SourcePressure: Codable, Equatable, Sendable {
        let listIdentifier: String
        let approximateRuleCount: Int
        let inputByteCount: Int
    }

    let configuredRuleLimit: Int?
    let wasHit: Bool
    let discardedRuleCount: Int
    let sourcePressure: [SourcePressure]

    static let none = NativeContentBlockingRuleCapDiagnostics(
        configuredRuleLimit: nil,
        wasHit: false,
        discardedRuleCount: 0,
        sourcePressure: []
    )
}

struct NativeContentBlockingCompilationSummary: Codable, Equatable, Sendable {
    let inputRuleCount: Int
    let inputByteCount: Int
    let convertedNetworkRuleCount: Int
    let convertedNativeCosmeticRuleCount: Int
    let unsupportedOrIgnoredRuleCount: Int
    let networkJSONByteCount: Int
    let nativeCosmeticJSONByteCount: Int
    let totalJSONByteCount: Int
    let ruleCap: NativeContentBlockingRuleCapDiagnostics
}

struct NativeContentBlockingLogicalGroupDescriptor: Codable, Equatable, Sendable {
    let id: SumiProtectionGroupKind
    let status: String?
    let ruleCount: Int
    let shardCount: Int
    let sourceName: String?
    let sourceURL: String?
    let sourceLicense: String?
    let sourceLicenseURL: String?
    let sourceAttribution: String?
    let sourceGeneratedAt: String?
    let sourceSha256: String?
    let sourceNonCommercialOnly: Bool?
    let sourceShareAlike: Bool?
    let sourceGenerator: String?
    let notes: [String]

    var reportLine: String {
        [
            "status=\(status ?? "nil")",
            "rules=\(ruleCount)",
            "shards=\(shardCount)",
            "sourceName=\(sourceName ?? "nil")",
            "sourceURL=\(sourceURL ?? "nil")",
            "sourceLicense=\(sourceLicense ?? "nil")",
            "sourceLicenseURL=\(sourceLicenseURL ?? "nil")",
            "sourceAttribution=\(sourceAttribution ?? "nil")",
            "sourceGeneratedAt=\(sourceGeneratedAt ?? "nil")",
            "sourceSha256=\(sourceSha256 ?? "nil")",
            "sourceNonCommercialOnly=\(sourceNonCommercialOnly.map(String.init) ?? "nil")",
            "sourceShareAlike=\(sourceShareAlike.map(String.init) ?? "nil")",
            "sourceGenerator=\(sourceGenerator ?? "nil")",
            "notes=\(notes.joined(separator: " | "))",
        ].joined(separator: "; ")
    }
}

struct NativeContentBlockingShardDescriptor: Codable, Equatable, Sendable {
    let id: String
    let generationId: String
    let kind: AdblockCompiledRuleGroupKind
    let sourceListIdentifiers: [String]
    let sourceCategories: [AdblockFilterListCategory]
    let protectionGroup: SumiProtectionGroupKind?
    let webKitIdentifier: String
    let contentHash: String
    let approximateRuleCount: Int
    let jsonByteCount: Int
    let compilerIdentity: NativeContentBlockingCompilerIdentity?
    let diagnosticsSummary: String

    init(
        id: String,
        generationId: String,
        kind: AdblockCompiledRuleGroupKind,
        sourceListIdentifiers: [String],
        sourceCategories: [AdblockFilterListCategory],
        protectionGroup: SumiProtectionGroupKind? = nil,
        webKitIdentifier: String,
        contentHash: String,
        approximateRuleCount: Int,
        jsonByteCount: Int,
        compilerIdentity: NativeContentBlockingCompilerIdentity?,
        diagnosticsSummary: String
    ) {
        self.id = id
        self.generationId = generationId
        self.kind = kind
        self.sourceListIdentifiers = sourceListIdentifiers
        self.sourceCategories = sourceCategories
        self.protectionGroup = protectionGroup
        self.webKitIdentifier = webKitIdentifier
        self.contentHash = contentHash
        self.approximateRuleCount = approximateRuleCount
        self.jsonByteCount = jsonByteCount
        self.compilerIdentity = compilerIdentity
        self.diagnosticsSummary = diagnosticsSummary
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case generationId
        case kind
        case sourceListIdentifiers
        case sourceCategories
        case protectionGroup
        case webKitIdentifier
        case contentHash
        case approximateRuleCount
        case jsonByteCount
        case compilerIdentity
        case diagnosticsSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        generationId = try container.decode(String.self, forKey: .generationId)
        kind = try container.decode(AdblockCompiledRuleGroupKind.self, forKey: .kind)
        sourceListIdentifiers = try container.decode([String].self, forKey: .sourceListIdentifiers)
        sourceCategories = try container.decode([AdblockFilterListCategory].self, forKey: .sourceCategories)
        protectionGroup = try container.decodeIfPresent(SumiProtectionGroupKind.self, forKey: .protectionGroup)
        webKitIdentifier = try container.decode(String.self, forKey: .webKitIdentifier)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        approximateRuleCount = try container.decode(Int.self, forKey: .approximateRuleCount)
        jsonByteCount = try container.decode(Int.self, forKey: .jsonByteCount)
        compilerIdentity = try container.decodeIfPresent(NativeContentBlockingCompilerIdentity.self, forKey: .compilerIdentity)
        diagnosticsSummary = try container.decode(String.self, forKey: .diagnosticsSummary)
    }
}
