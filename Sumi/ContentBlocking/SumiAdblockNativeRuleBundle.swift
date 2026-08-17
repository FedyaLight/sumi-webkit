import Foundation
import SumiDomain

enum SumiAdblockNativeRuleBundleError: Error, LocalizedError, Equatable {
    case missingManifest(URL)
    case unsupportedSchemaVersion(Int)
    case missingShard(String)
    case emptyShard(String)
    case invalidShardPath(String)
    case shardHashMismatch(path: String, expected: String, actual: String)
    case shardSizeMismatch(path: String, expected: Int, actual: Int)
    case invalidShardJSON(String)
    case missingAdvancedArtifact(String)
    case emptyAdvancedArtifact(String)
    case invalidAdvancedArtifactPath(String)
    case advancedArtifactHashMismatch(path: String, expected: String, actual: String)
    case advancedArtifactSizeMismatch(path: String, expected: Int, actual: Int)
    case invalidAdvancedDescriptor(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest(let url):
            return "Missing embedded Adblock bundle manifest: \(url.path)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported embedded Adblock bundle schema version: \(version)"
        case .missingShard(let path):
            return "Missing embedded Adblock bundle shard: \(path)"
        case .emptyShard(let path):
            return "Embedded Adblock bundle shard is empty: \(path)"
        case .invalidShardPath(let path):
            return "Embedded Adblock bundle shard path is invalid: \(path)"
        case .shardHashMismatch(let path, let expected, let actual):
            return "Embedded Adblock bundle shard hash mismatch for \(path): expected \(expected), got \(actual)"
        case .shardSizeMismatch(let path, let expected, let actual):
            return "Embedded Adblock bundle shard size mismatch for \(path): expected \(expected), got \(actual)"
        case .invalidShardJSON(let path):
            return "Embedded Adblock bundle shard JSON is invalid: \(path)"
        case .missingAdvancedArtifact(let path):
            return "Missing prepared advanced-blocking artifact: \(path)"
        case .emptyAdvancedArtifact(let path):
            return "Prepared advanced-blocking artifact is empty: \(path)"
        case .invalidAdvancedArtifactPath(let path):
            return "Prepared advanced-blocking artifact path is invalid: \(path)"
        case .advancedArtifactHashMismatch(let path, let expected, let actual):
            return "Prepared advanced-blocking artifact hash mismatch for \(path): expected \(expected), got \(actual)"
        case .advancedArtifactSizeMismatch(let path, let expected, let actual):
            return "Prepared advanced-blocking artifact size mismatch for \(path): expected \(expected), got \(actual)"
        case .invalidAdvancedDescriptor(let reason):
            return "Prepared advanced-blocking descriptor is invalid: \(reason)"
        }
    }
}

struct SumiAdblockNativeRuleBundleManifest: Codable, Equatable, Sendable {
    struct SourceList: Codable, Equatable, Sendable {
        let id: String
        let displayName: String
        let hash: String
        let byteSize: Int
        let ruleCount: Int
        let category: AdblockFilterListCategory?
    }

    struct Shard: Codable, Equatable, Sendable {
        let kind: String
        let group: String
        let logicalGroup: String?
        let relativePath: String
        let hash: String
        let byteSize: Int
        let ruleCount: Int
        let webKitIdentifier: String

        var ruleGroupKind: AdblockCompiledRuleGroupKind {
            switch kind {
            case "network":
                return .network
            case "nativeCSS":
                return .nativeCosmeticCSS
            case "cosmeticJS":
                return .cosmeticJS
            default:
                return .unsupported
            }
        }

        func protectionGroupKind(
            bundleProfileId: String
        ) -> SumiProtectionGroupKind? {
            if let logicalGroup,
               let group = SumiProtectionGroupKind(rawValue: logicalGroup) {
                return group
            }
            if let group = SumiProtectionGroupKind(rawValue: group) {
                return group
            }
            if bundleProfileId == SumiProtectionBundleProfile.adblock,
               ruleGroupKind == .network {
                return .adblockAdsPrivacyNetwork
            }
            return nil
        }
    }

    let schemaVersion: Int
    let bundleId: String
    let generationId: String
    let profileId: String
    let lists: [SourceList]
    let shards: [Shard]
    let advancedBlocking: AdvancedBlockingGenerationDescriptor?
}

struct SumiAdblockNativeRuleBundle: Sendable {
    static let directoryName = "SumiAdblockBundle"
    static let manifestFileName = "manifest.json"
    let directoryURL: URL
    let manifest: SumiAdblockNativeRuleBundleManifest
}
