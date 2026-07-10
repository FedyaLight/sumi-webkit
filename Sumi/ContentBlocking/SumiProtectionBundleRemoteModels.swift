import Foundation
import SumiDomain

enum SumiRemoteAdblockBundleCache {
    static let metadataFileName = "remote-release.json"

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Sumi/AdblockRemoteBundles", isDirectory: true)
    }

    static func bundleURL(profileId: String, rootDirectory: URL = defaultRootDirectory()) -> URL {
        rootDirectory
            .appendingPathComponent(profileId, isDirectory: true)
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
    }
}

enum SumiProtectionBundleRemoteUpdateConstants {
    static let owner = "FedyaLight"
    static let repository = "sumi-protection-bundles"
    static let releaseManifestAssetName = "sumi-protection-bundles-release.json"
    static let releaseManifestSignatureAssetName = "sumi-protection-bundles-release.json.sig"
    static let releaseManifestSchemaVersion = 1
    static let browserBundleExpectationVersion = 1
    static let maximumAssetByteCount = 50_000_000
}

enum SumiProtectionBundleRemoteUpdateError: Error, LocalizedError, Equatable {
    case releaseIsNotApproved
    case releaseManifestAssetMissing(String)
    case releaseManifestSignatureAssetMissing(String)
    case signatureMetadataMalformed(String)
    case signatureAlgorithmUnsupported(String)
    case signatureKeyUnknown(String)
    case signaturePublicKeyInvalid(String)
    case signatureInvalid(String)
    case releaseManifestSchemaUnsupported(Int)
    case releaseManifestIncompatible(String)
    case releaseDowngradeRejected(current: String, incoming: String)
    case profileMissing(String)
    case assetMissing(String)
    case duplicateAssetName(String)
    case duplicateBundleProfile(String)
    case duplicateBundleAssetName(String)
    case duplicateBundleRelativePath(String)
    case assetSizeMismatch(name: String, expected: Int, actual: Int)
    case assetHashMismatch(name: String, expected: String, actual: String)
    case assetTooLarge(name: String, byteCount: Int)
    case invalidRelativePath(String)
    case bundleMetadataMismatch(String)
    case cacheCommitFailed(String)
    case cacheRollbackFailed(commit: String, rollback: String)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .releaseIsNotApproved:
            return "Latest bundle release is not approved for browser consumption."
        case .releaseManifestAssetMissing(let name):
            return "Release manifest asset is missing: \(name)."
        case .releaseManifestSignatureAssetMissing(let name):
            return "Release manifest signature asset is missing: \(name)."
        case .signatureMetadataMalformed(let detail):
            return "Release manifest signature metadata is malformed: \(detail)"
        case .signatureAlgorithmUnsupported(let algorithm):
            return "Release manifest signature algorithm is unsupported: \(algorithm)."
        case .signatureKeyUnknown(let keyId):
            return "Release manifest signing key is not pinned by this Sumi build: \(keyId)."
        case .signaturePublicKeyInvalid(let keyId):
            return "Pinned release manifest public key is invalid: \(keyId)."
        case .signatureInvalid(let keyId):
            return "Release manifest signature verification failed for key \(keyId)."
        case .releaseManifestSchemaUnsupported(let version):
            return "Unsupported bundle release manifest schema: \(version)."
        case .releaseManifestIncompatible(let detail):
            return "Bundle release is incompatible with this Sumi build: \(detail)"
        case .releaseDowngradeRejected(let current, let incoming):
            return "Bundle release downgrade rejected: installed \(current), remote \(incoming)."
        case .profileMissing(let profileId):
            return "Release does not contain required bundle profile \(profileId)."
        case .assetMissing(let name):
            return "Release asset is missing: \(name)."
        case .duplicateAssetName(let name):
            return "Release contains duplicate asset name: \(name)."
        case .duplicateBundleProfile(let profileId):
            return "Release manifest contains duplicate bundle profile: \(profileId)."
        case .duplicateBundleAssetName(let name):
            return "Bundle manifest contains duplicate asset name: \(name)."
        case .duplicateBundleRelativePath(let path):
            return "Bundle manifest contains duplicate destination path: \(path)."
        case .assetSizeMismatch(let name, let expected, let actual):
            return "Release asset \(name) size mismatch: expected \(expected), got \(actual)."
        case .assetHashMismatch(let name, let expected, let actual):
            return "Release asset \(name) SHA-256 mismatch: expected \(expected), got \(actual)."
        case .assetTooLarge(let name, let byteCount):
            return "Release asset \(name) is too large: \(byteCount) bytes."
        case .invalidRelativePath(let path):
            return "Release asset has invalid bundle path: \(path)."
        case .bundleMetadataMismatch(let detail):
            return "Downloaded bundle metadata mismatch: \(detail)"
        case .cacheCommitFailed(let detail):
            return "Remote bundle cache commit failed: \(detail)"
        case .cacheRollbackFailed(let commit, let rollback):
            return "Remote bundle cache commit failed: \(commit); rollback failed: \(rollback)"
        case .httpStatus(let status, let url):
            return "Bundle update request failed with HTTP \(status): \(url)"
        }
    }
}

struct SumiProtectionBundleGitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let size: Int
        let browserDownloadURL: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    let tagName: String
    let htmlURL: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case publishedAt = "published_at"
        case assets
    }
}

struct SumiProtectionBundleReleaseManifest: Decodable, Sendable {
    struct Repository: Decodable, Equatable, Sendable {
        let owner: String
        let name: String
        let commit: String?
    }

    struct Compatibility: Decodable, Equatable, Sendable {
        let minimumSumiBundleExpectationVersion: Int
        let maximumSumiBundleExpectationVersion: Int
        let bundleManifestSchemaVersion: Int
        let requiredNativeCSSSafetyPolicyVersion: String
    }

    struct Bundle: Decodable, Equatable, Sendable {
        struct Group: Decodable, Equatable, Sendable {
            struct Source: Decodable, Equatable, Sendable {
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
            let status: String?
            let ruleCount: Int
            let shardCount: Int
            let assetNames: [String]
            let source: Source?
        }

        let profileId: String
        let bundleId: String
        let generationId: String
        let generatedDate: String
        let groups: [Group]?
        let assetNames: [String]
    }

    enum AssetRole: String, Decodable, Equatable, Sendable {
        case bundleManifest
        case diagnostics
        case trackingNetworkShard
        case networkShard
        case cosmeticShard
        case nativeCSSShard
    }

    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let role: AssetRole
        let bundleProfileId: String
        let groupId: SumiProtectionGroupKind?
        let relativePath: String
        let byteSize: Int
        let sha256: String
    }

    let schemaVersion: Int
    let releaseVersion: String
    let generatedAt: String
    let repository: Repository
    let compatibility: Compatibility
    let bundles: [Bundle]
    let assets: [Asset]
}

struct SumiProtectionRemoteBundleFetchResult: Equatable, Sendable {
    let profileId: String
    let releaseVersion: String
    let releaseTag: String
    let releaseURL: String?
    let publishedDate: Date?
    let manifestSignatureRequired: Bool
    let manifestSignatureVerified: Bool
    let signingKeyId: String
    let signingKeyVersion: Int
    let bundleId: String
    let generationId: String
    let bundleURL: URL
}

protocol SumiProtectionBundleRemoteUpdating: AnyObject, Sendable {
    func fetchLatestApprovedBundle(profileId: String) async throws -> SumiProtectionRemoteBundleFetchResult
}

struct SumiProtectionBundleIdentity: Equatable, Sendable {
    let profileId: String
    let bundleId: String
    let generationId: String
}

enum SumiProtectionBundleManualUpdateActivation: String, Codable, Equatable, Sendable {
    case cachedOnly
    case alreadyCurrent
    case installedRestartRequired
}

struct SumiProtectionBundleManualUpdateOutcome: Equatable, Sendable {
    let profileId: String
    let releaseVersion: String
    let releaseTag: String
    let bundleId: String
    let generationId: String
    let manifestSignatureRequired: Bool
    let manifestSignatureVerified: Bool
    let signingKeyId: String
    let signingKeyVersion: Int
    let activation: SumiProtectionBundleManualUpdateActivation
    let browserRestartRequired: Bool
    let summary: String
}
