import Combine
import CryptoKit
import Foundation

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

    static func remoteMetadata(
        bundleURL: URL,
        fileManager: FileManager = .default
    ) -> SumiAdblockPreparedBundleRemoteMetadata? {
        let metadataURL = bundleURL.appendingPathComponent(metadataFileName)
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL)
        else { return nil }
        return try? JSONDecoder().decode(SumiAdblockPreparedBundleRemoteMetadata.self, from: data)
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
    case assetSizeMismatch(name: String, expected: Int, actual: Int)
    case assetHashMismatch(name: String, expected: String, actual: String)
    case assetTooLarge(name: String, byteCount: Int)
    case invalidRelativePath(String)
    case bundleMetadataMismatch(String)
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

protocol SumiProtectionBundleReleaseFetching: Sendable {
    func latestRelease() async throws -> SumiProtectionBundleGitHubRelease
    func data(from url: URL) async throws -> Data
}

final class SumiProtectionBundleGitHubReleaseClient: SumiProtectionBundleReleaseFetching, @unchecked Sendable {
    private let latestReleaseURL: URL
    private let session: URLSession

    init(
        owner: String = SumiProtectionBundleRemoteUpdateConstants.owner,
        repository: String = SumiProtectionBundleRemoteUpdateConstants.repository,
        session: URLSession = .shared
    ) {
        latestReleaseURL = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
        self.session = session
    }

    func latestRelease() async throws -> SumiProtectionBundleGitHubRelease {
        let data = try await data(from: latestReleaseURL)
        return try JSONDecoder().decode(SumiProtectionBundleGitHubRelease.self, from: data)
    }

    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SumiBundleUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw SumiProtectionBundleRemoteUpdateError.httpStatus(response.statusCode, url.absoluteString)
        }
        return data
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
        let profileId: String
        let bundleId: String
        let generationId: String
        let generatedDate: String
        let assetNames: [String]
    }

    enum AssetRole: String, Decodable, Equatable, Sendable {
        case bundleManifest
        case diagnostics
        case trackingNetworkShard
        case networkShard
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

    func validate() throws {
        guard schemaVersion == SumiProtectionBundleRemoteUpdateConstants.releaseManifestSchemaVersion else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestSchemaUnsupported(schemaVersion)
        }
        let expectation = SumiProtectionBundleRemoteUpdateConstants.browserBundleExpectationVersion
        guard compatibility.minimumSumiBundleExpectationVersion <= expectation,
              compatibility.maximumSumiBundleExpectationVersion >= expectation
        else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestIncompatible(
                "browser expectation \(expectation) is outside \(compatibility.minimumSumiBundleExpectationVersion)-\(compatibility.maximumSumiBundleExpectationVersion)"
            )
        }
        guard compatibility.bundleManifestSchemaVersion == 1 else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestIncompatible(
                "bundle manifest schema \(compatibility.bundleManifestSchemaVersion) is unsupported"
            )
        }
        guard compatibility.requiredNativeCSSSafetyPolicyVersion == SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestIncompatible(
                "native CSS safety policy \(compatibility.requiredNativeCSSSafetyPolicyVersion) is unsupported"
            )
        }
    }

    func bundle(profileId: String) -> Bundle? {
        bundles.first { $0.profileId == profileId }
    }

    func assets(for bundle: Bundle) -> [Asset] {
        let names = Set(bundle.assetNames)
        return assets.filter { names.contains($0.name) && $0.bundleProfileId == bundle.profileId }
    }
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

actor SumiProtectionBundleRemoteUpdater: SumiProtectionBundleRemoteUpdating {
    private let fetcher: SumiProtectionBundleReleaseFetching
    private let signatureVerifier: any SumiProtectionBundleManifestVerifying
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let isoDateFormatter = ISO8601DateFormatter()

    init(
        fetcher: SumiProtectionBundleReleaseFetching = SumiProtectionBundleGitHubReleaseClient(),
        signatureVerifier: any SumiProtectionBundleManifestVerifying = SumiProtectionBundleSignatureVerifier(),
        rootDirectory: URL = SumiRemoteAdblockBundleCache.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.fetcher = fetcher
        self.signatureVerifier = signatureVerifier
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func fetchLatestApprovedBundle(profileId: String) async throws -> SumiProtectionRemoteBundleFetchResult {
        let release = try await fetcher.latestRelease()
        guard !release.draft, !release.prerelease else {
            throw SumiProtectionBundleRemoteUpdateError.releaseIsNotApproved
        }
        let releaseAssets = Dictionary(uniqueKeysWithValues: release.assets.map { ($0.name, $0) })
        guard let releaseManifestAsset = releaseAssets[SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName] else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestAssetMissing(
                SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName
            )
        }
        guard let releaseManifestSignatureAsset = releaseAssets[SumiProtectionBundleRemoteUpdateConstants.releaseManifestSignatureAssetName] else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestSignatureAssetMissing(
                SumiProtectionBundleRemoteUpdateConstants.releaseManifestSignatureAssetName
            )
        }

        let releaseManifestData = try await verifiedData(
            for: releaseManifestAsset,
            expectedHash: githubDigestSHA256(releaseManifestAsset.digest),
            expectedByteSize: releaseManifestAsset.size
        )
        let releaseManifestSignatureData = try await verifiedData(
            for: releaseManifestSignatureAsset,
            expectedHash: githubDigestSHA256(releaseManifestSignatureAsset.digest),
            expectedByteSize: releaseManifestSignatureAsset.size
        )
        let signatureVerification = try signatureVerifier.verify(
            manifestData: releaseManifestData,
            signatureData: releaseManifestSignatureData,
            expectedSignedAsset: SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName
        )
        let manifest = try JSONDecoder().decode(SumiProtectionBundleReleaseManifest.self, from: releaseManifestData)
        try manifest.validate()
        try rejectDowngradeIfNeeded(profileId: profileId, incomingReleaseVersion: manifest.releaseVersion)
        guard let bundle = manifest.bundle(profileId: profileId) else {
            throw SumiProtectionBundleRemoteUpdateError.profileMissing(profileId)
        }
        let bundleAssets = manifest.assets(for: bundle)
        guard Set(bundle.assetNames) == Set(bundleAssets.map(\.name)) else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestIncompatible(
                "bundle \(profileId) asset list is incomplete"
            )
        }

        let stagingBundleURL = try stagingBundleDirectory()
        let stagingRoot = stagingBundleURL.deletingLastPathComponent()
        defer { try? fileManager.removeItem(at: stagingRoot) }

        for descriptor in bundleAssets {
            guard let releaseAsset = releaseAssets[descriptor.name] else {
                throw SumiProtectionBundleRemoteUpdateError.assetMissing(descriptor.name)
            }
            guard releaseAsset.size == descriptor.byteSize else {
                throw SumiProtectionBundleRemoteUpdateError.assetSizeMismatch(
                    name: descriptor.name,
                    expected: descriptor.byteSize,
                    actual: releaseAsset.size
                )
            }
            let data = try await verifiedData(
                for: releaseAsset,
                expectedHash: descriptor.sha256,
                expectedByteSize: descriptor.byteSize
            )
            let destination = try safeDestinationURL(
                bundleURL: stagingBundleURL,
                relativePath: descriptor.relativePath
            )
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
        }

        let metadata = SumiAdblockPreparedBundleRemoteMetadata(
            releaseVersion: manifest.releaseVersion,
            releaseTag: release.tagName,
            releaseURL: release.htmlURL,
            publishedDate: release.publishedAt.flatMap { isoDateFormatter.date(from: $0) },
            manifestSignatureRequired: SumiProtectionBundleTrust.remoteManifestSignatureRequired,
            manifestSignatureVerified: true,
            signingKeyId: signatureVerification.keyId,
            signingKeyVersion: signatureVerification.keyVersion
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(
            to: stagingBundleURL.appendingPathComponent(SumiRemoteAdblockBundleCache.metadataFileName),
            options: .atomic
        )

        let downloadedBundle = try SumiAdblockNativeRuleBundle.load(directoryURL: stagingBundleURL, fileManager: fileManager)
        guard downloadedBundle.manifest.profileId == profileId,
              downloadedBundle.manifest.bundleId == bundle.bundleId,
              downloadedBundle.manifest.generationId == bundle.generationId
        else {
            throw SumiProtectionBundleRemoteUpdateError.bundleMetadataMismatch(
                "expected \(bundle.bundleId)/\(bundle.generationId), got \(downloadedBundle.manifest.bundleId)/\(downloadedBundle.manifest.generationId)"
            )
        }

        let cachedBundleURL = try commitCachedBundle(stagedBundleURL: stagingBundleURL, profileId: profileId)
        return SumiProtectionRemoteBundleFetchResult(
            profileId: profileId,
            releaseVersion: manifest.releaseVersion,
            releaseTag: release.tagName,
            releaseURL: release.htmlURL,
            publishedDate: metadata.publishedDate,
            manifestSignatureRequired: SumiProtectionBundleTrust.remoteManifestSignatureRequired,
            manifestSignatureVerified: true,
            signingKeyId: signatureVerification.keyId,
            signingKeyVersion: signatureVerification.keyVersion,
            bundleId: bundle.bundleId,
            generationId: bundle.generationId,
            bundleURL: cachedBundleURL
        )
    }

    private func rejectDowngradeIfNeeded(
        profileId: String,
        incomingReleaseVersion: String
    ) throws {
        let currentBundleURL = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: rootDirectory
        )
        guard let current = SumiRemoteAdblockBundleCache.remoteMetadata(
            bundleURL: currentBundleURL,
            fileManager: fileManager
        )?.releaseVersion else { return }
        guard Self.compareReleaseVersions(incomingReleaseVersion, current) != .orderedAscending else {
            throw SumiProtectionBundleRemoteUpdateError.releaseDowngradeRejected(
                current: current,
                incoming: incomingReleaseVersion
            )
        }
    }

    private func stagingBundleDirectory() throws -> URL {
        let stagingURL = rootDirectory
            .appendingPathComponent("Staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        return stagingURL
    }

    private func commitCachedBundle(stagedBundleURL: URL, profileId: String) throws -> URL {
        let destination = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: rootDirectory
        )
        let profileRoot = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: profileRoot, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destination.path) {
            let backupName = ".\(SumiAdblockNativeRuleBundle.directoryName).previous-\(UUID().uuidString)"
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: stagedBundleURL,
                backupItemName: backupName,
                options: []
            )
            try? fileManager.removeItem(at: profileRoot.appendingPathComponent(backupName))
        } else {
            try fileManager.moveItem(at: stagedBundleURL, to: destination)
        }
        _ = try SumiAdblockNativeRuleBundle.load(directoryURL: destination, fileManager: fileManager)
        return destination
    }

    private func verifiedData(
        for asset: SumiProtectionBundleGitHubRelease.Asset,
        expectedHash: String?,
        expectedByteSize: Int
    ) async throws -> Data {
        guard expectedByteSize <= SumiProtectionBundleRemoteUpdateConstants.maximumAssetByteCount else {
            throw SumiProtectionBundleRemoteUpdateError.assetTooLarge(
                name: asset.name,
                byteCount: expectedByteSize
            )
        }
        let data = try await fetcher.data(from: asset.browserDownloadURL)
        guard data.count == expectedByteSize else {
            throw SumiProtectionBundleRemoteUpdateError.assetSizeMismatch(
                name: asset.name,
                expected: expectedByteSize,
                actual: data.count
            )
        }
        if let expectedHash {
            let actualHash = Self.sha256Hex(data)
            guard actualHash == expectedHash else {
                throw SumiProtectionBundleRemoteUpdateError.assetHashMismatch(
                    name: asset.name,
                    expected: expectedHash,
                    actual: actualHash
                )
            }
        }
        return data
    }

    private func safeDestinationURL(bundleURL: URL, relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..")
        else {
            throw SumiProtectionBundleRemoteUpdateError.invalidRelativePath(relativePath)
        }
        let destination = bundleURL.appendingPathComponent(relativePath)
        let root = bundleURL.standardizedFileURL.path
        let candidate = destination.standardizedFileURL.path
        guard candidate.hasPrefix(root + "/") else {
            throw SumiProtectionBundleRemoteUpdateError.invalidRelativePath(relativePath)
        }
        return destination
    }

    private func githubDigestSHA256(_ digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        return String(digest.dropFirst("sha256:".count))
    }

    private static func compareReleaseVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [.numeric])
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
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

@MainActor
final class SumiProtectionBundleUpdateStatusStore: ObservableObject {
    static let shared = SumiProtectionBundleUpdateStatusStore()

    private enum DefaultsKey {
        static let lastAttemptDate = "settings.protection.bundleUpdate.lastAttemptDate"
        static let lastSuccessDate = "settings.protection.bundleUpdate.lastSuccessDate"
        static let lastReleaseVersion = "settings.protection.bundleUpdate.lastReleaseVersion"
        static let lastBundleId = "settings.protection.bundleUpdate.lastBundleId"
        static let lastSummary = "settings.protection.bundleUpdate.lastSummary"
        static let lastFailureReason = "settings.protection.bundleUpdate.lastFailureReason"
        static let lastSignatureVerified = "settings.protection.bundleUpdate.lastSignatureVerified"
        static let lastSigningKeyId = "settings.protection.bundleUpdate.lastSigningKeyId"
        static let lastSigningKeyVersion = "settings.protection.bundleUpdate.lastSigningKeyVersion"
        static let lastSignatureError = "settings.protection.bundleUpdate.lastSignatureError"
        static let lastDowngradeRejected = "settings.protection.bundleUpdate.lastDowngradeRejected"
    }

    @Published private(set) var lastAttemptDate: Date?
    @Published private(set) var lastSuccessDate: Date?
    @Published private(set) var lastReleaseVersion: String?
    @Published private(set) var lastBundleId: String?
    @Published private(set) var lastSummary: String?
    @Published private(set) var lastFailureReason: String?
    @Published private(set) var lastSignatureVerified: Bool?
    @Published private(set) var lastSigningKeyId: String?
    @Published private(set) var lastSigningKeyVersion: Int?
    @Published private(set) var lastSignatureError: String?
    @Published private(set) var lastDowngradeRejected: Bool?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        lastAttemptDate = userDefaults.object(forKey: DefaultsKey.lastAttemptDate) as? Date
        lastSuccessDate = userDefaults.object(forKey: DefaultsKey.lastSuccessDate) as? Date
        lastReleaseVersion = userDefaults.string(forKey: DefaultsKey.lastReleaseVersion)
        lastBundleId = userDefaults.string(forKey: DefaultsKey.lastBundleId)
        lastSummary = userDefaults.string(forKey: DefaultsKey.lastSummary)
        lastFailureReason = userDefaults.string(forKey: DefaultsKey.lastFailureReason)
        if userDefaults.object(forKey: DefaultsKey.lastSignatureVerified) != nil {
            lastSignatureVerified = userDefaults.bool(forKey: DefaultsKey.lastSignatureVerified)
        }
        lastSigningKeyId = userDefaults.string(forKey: DefaultsKey.lastSigningKeyId)
        if userDefaults.object(forKey: DefaultsKey.lastSigningKeyVersion) != nil {
            lastSigningKeyVersion = userDefaults.integer(forKey: DefaultsKey.lastSigningKeyVersion)
        }
        lastSignatureError = userDefaults.string(forKey: DefaultsKey.lastSignatureError)
        if userDefaults.object(forKey: DefaultsKey.lastDowngradeRejected) != nil {
            lastDowngradeRejected = userDefaults.bool(forKey: DefaultsKey.lastDowngradeRejected)
        }
    }

    func recordSuccess(_ outcome: SumiProtectionBundleManualUpdateOutcome, date: Date = Date()) {
        lastAttemptDate = date
        lastSuccessDate = date
        lastReleaseVersion = outcome.releaseVersion
        lastBundleId = outcome.bundleId
        lastSummary = outcome.summary
        lastFailureReason = nil
        lastSignatureVerified = outcome.manifestSignatureVerified
        lastSigningKeyId = outcome.signingKeyId
        lastSigningKeyVersion = outcome.signingKeyVersion
        lastSignatureError = nil
        lastDowngradeRejected = false
        persist()
    }

    func recordFailure(_ error: Error, date: Date = Date()) {
        lastAttemptDate = date
        lastSummary = nil
        lastFailureReason = error.localizedDescription
        lastSignatureVerified = false
        if let signatureError = Self.signatureFailureSummary(error) {
            lastSignatureError = signatureError
        }
        lastDowngradeRejected = Self.isDowngradeRejection(error)
        persist()
    }

    private func persist() {
        setOrRemove(lastAttemptDate, forKey: DefaultsKey.lastAttemptDate)
        setOrRemove(lastSuccessDate, forKey: DefaultsKey.lastSuccessDate)
        setOrRemove(lastReleaseVersion, forKey: DefaultsKey.lastReleaseVersion)
        setOrRemove(lastBundleId, forKey: DefaultsKey.lastBundleId)
        setOrRemove(lastSummary, forKey: DefaultsKey.lastSummary)
        setOrRemove(lastFailureReason, forKey: DefaultsKey.lastFailureReason)
        setOrRemove(lastSignatureVerified, forKey: DefaultsKey.lastSignatureVerified)
        setOrRemove(lastSigningKeyId, forKey: DefaultsKey.lastSigningKeyId)
        setOrRemove(lastSigningKeyVersion, forKey: DefaultsKey.lastSigningKeyVersion)
        setOrRemove(lastSignatureError, forKey: DefaultsKey.lastSignatureError)
        setOrRemove(lastDowngradeRejected, forKey: DefaultsKey.lastDowngradeRejected)
    }

    private func setOrRemove(_ value: Any?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private static func signatureFailureSummary(_ error: Error) -> String? {
        guard let remoteError = error as? SumiProtectionBundleRemoteUpdateError else { return nil }
        switch remoteError {
        case .releaseManifestSignatureAssetMissing,
             .signatureMetadataMalformed,
             .signatureAlgorithmUnsupported,
             .signatureKeyUnknown,
             .signaturePublicKeyInvalid,
             .signatureInvalid:
            return remoteError.localizedDescription
        default:
            return nil
        }
    }

    private static func isDowngradeRejection(_ error: Error) -> Bool {
        guard let remoteError = error as? SumiProtectionBundleRemoteUpdateError else { return false }
        if case .releaseDowngradeRejected = remoteError {
            return true
        }
        return false
    }
}
