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
    case unsupportedNativeCSSSafetyPolicyVersion(String?)
    case manifestChangedDuringValidation

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
        case .unsupportedNativeCSSSafetyPolicyVersion(let version):
            return "Embedded Adblock bundle native CSS safety policy is unsupported: \(version ?? "missing")"
        case .manifestChangedDuringValidation:
            return "Embedded Adblock bundle manifest changed while its payload was being validated."
        }
    }
}

struct SumiAdblockNativeRuleBundleManifest: Codable, Equatable, Sendable {
    struct Compiler: Codable, Equatable, Sendable {
        let name: String
        let version: String
    }

    struct SourceList: Codable, Equatable, Sendable {
        let id: String
        let displayName: String
        let url: String
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

    struct DedupeSummary: Codable, Equatable, Sendable {
        let inputRawRuleCount: Int
        let rawDuplicateCountRemoved: Int
        let nativeJSONDuplicateCountRemoved: Int
        let skippedDedupeCount: Int
        let skippedDedupeReasons: [String: Int]
        let finalRuleCount: Int
        let finalShardCount: Int
    }

    struct DiagnosticsSummary: Codable, Equatable, Sendable {
        let inputRuleCount: Int
        let finalRuleCount: Int
        let finalShardCount: Int
        let networkRuleCount: Int
        let nativeCSSRuleCount: Int
        let unsafeCSSFilteredCount: Int
        let warnings: [String]
    }

    struct Group: Codable, Equatable, Sendable {
        struct Source: Codable, Equatable, Sendable {
            let type: String?
            let name: String?
            let sourceName: String?
            let url: String?
            let sourceURL: String?
            let license: String?
            let sourceLicense: String?
            let sourceLicenseURL: String?
            let attribution: String?
            let generatedAt: String?
            let sourceSha256: String?
            let sourceByteSize: Int?
            let ruleCount: Int?
            let shardCount: Int?
            let nonCommercialOnly: Bool?
            let shareAlike: Bool?
            let generator: String?
        }

        let id: SumiProtectionGroupKind
        let displayName: String?
        let status: String?
        let activeLevels: [String]?
        let ruleCount: Int
        let shardCount: Int
        let assetRelativePaths: [String]?
        let source: Source?
        let notes: [String]?
    }

    let schemaVersion: Int
    let bundleId: String
    let generationId: String
    let profileId: String
    let compiler: Compiler
    let nativeCSSSafetyPolicyVersion: String?
    let generatedDate: String
    let lists: [SourceList]
    let profileLevelMapping: [String: [SumiProtectionGroupKind]]?
    let groups: [Group]?
    let shards: [Shard]
    let diagnosticsSummary: DiagnosticsSummary
    let unsafeCSSFilteredCount: Int
    let deduplication: DedupeSummary
}

struct SumiAdblockNativeRuleBundle: Sendable {
    static let directoryName = "SumiAdblockBundle"
    static let manifestFileName = "manifest.json"
    static let requiredNativeCSSSafetyPolicyVersion =
        "sumi-native-css-safety/0.4"

    let directoryURL: URL
    let manifest: SumiAdblockNativeRuleBundleManifest
}
