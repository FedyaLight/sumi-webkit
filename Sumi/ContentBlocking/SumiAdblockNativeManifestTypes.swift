import Foundation
import SumiDomain

enum AdblockCompiledRuleGroupKind: String, Codable, CaseIterable, Hashable, Sendable {
    case network
    case nativeCosmeticCSS
    case cosmeticJS
    case unsupported
}

enum AdvancedBlockingArtifactRole: String, Codable, CaseIterable, Sendable {
    case ruleStorage
    case engineIndex
    case engineMetadata
    case sourceRules
    case urlCleaningRules
}

/// The complete prepared advanced-filtering half of one blocker generation.
/// Native WebKit shards and this descriptor are published by the archive as a
/// single transaction, so exceptions cannot be evaluated against another
/// generation's cosmetic or scriptlet rules.
struct AdvancedBlockingGenerationDescriptor: Codable, Equatable, Sendable {
    struct Artifact: Codable, Equatable, Sendable {
        let role: AdvancedBlockingArtifactRole
        let relativePath: String
        let hash: String
        let byteSize: Int
    }

    static let safariConverterFormat = "safari-converter-filter-engine"

    let format: String
    let schemaVersion: Int
    let runtimeVersion: String
    let ruleCount: Int
    let artifacts: [Artifact]
}

struct NativeContentBlockingShardDescriptor: Codable, Equatable, Sendable {
    let id: String
    let generationId: String
    let kind: AdblockCompiledRuleGroupKind
    let protectionGroup: SumiProtectionGroupKind?
    let webKitIdentifier: String
    let contentHash: String
    let approximateRuleCount: Int
    let jsonByteCount: Int

    init(
        id: String,
        generationId: String,
        kind: AdblockCompiledRuleGroupKind,
        protectionGroup: SumiProtectionGroupKind? = nil,
        webKitIdentifier: String,
        contentHash: String,
        approximateRuleCount: Int,
        jsonByteCount: Int
    ) {
        self.id = id
        self.generationId = generationId
        self.kind = kind
        self.protectionGroup = protectionGroup
        self.webKitIdentifier = webKitIdentifier
        self.contentHash = contentHash
        self.approximateRuleCount = approximateRuleCount
        self.jsonByteCount = jsonByteCount
    }
}
