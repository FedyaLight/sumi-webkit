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

struct NativeContentBlockingShardDescriptor: Codable, Equatable, Sendable {
    let id: String
    let generationId: String
    let kind: AdblockCompiledRuleGroupKind
    let sourceListIdentifiers: [String]
    let sourceCategories: [AdblockFilterListCategory]
    let webKitIdentifier: String
    let contentHash: String
    let approximateRuleCount: Int
    let jsonByteCount: Int
    let compilerIdentity: NativeContentBlockingCompilerIdentity?
    let diagnosticsSummary: String
}
