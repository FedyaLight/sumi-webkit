import CryptoKit
import Foundation
import OSLog

/// The filesystem boundary for prepared native rule bundles. All manifest and
/// shard reads pass through the same path, size, hash, and JSON validation.
struct SumiAdblockNativeBundleReader: @unchecked Sendable {
    private static let log = Logger.sumi(category: "ContentBlocking")

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func bundledDirectoryURL(
        for profileId: String,
        in bundle: Bundle = .main
    ) -> URL? {
        guard let resourceURL = bundle.resourceURL else { return nil }
        return bundledDirectoryURL(
            for: profileId,
            resourceURL: resourceURL
        )
    }

    func bundledDirectoryURL(
        for profileId: String,
        resourceURL: URL
    ) -> URL? {
        let candidates = [
            resourceURL
                .appendingPathComponent(
                    "SumiAdblockBundles",
                    isDirectory: true
                )
                .appendingPathComponent(profileId, isDirectory: true)
                .appendingPathComponent(
                    SumiAdblockNativeRuleBundle.directoryName,
                    isDirectory: true
                ),
            resourceURL
                .appendingPathComponent(profileId, isDirectory: true)
                .appendingPathComponent(
                    SumiAdblockNativeRuleBundle.directoryName,
                    isDirectory: true
                ),
            resourceURL.appendingPathComponent(
                SumiAdblockNativeRuleBundle.directoryName,
                isDirectory: true
            ),
        ]

        for candidate in candidates {
            let manifestURL = candidate.appendingPathComponent(
                SumiAdblockNativeRuleBundle.manifestFileName
            )
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                continue
            }

            do {
                let ruleBundle = try load(from: candidate)
                guard ruleBundle.manifest.profileId == profileId else {
                    continue
                }
                return candidate
            } catch {
                Self.log.error(
                    "Embedded Adblock bundle candidate failed to load at \(candidate.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return nil
    }

    func load(from directoryURL: URL) throws -> SumiAdblockNativeRuleBundle {
        let manifestURL = directoryURL.appendingPathComponent(
            SumiAdblockNativeRuleBundle.manifestFileName
        )
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SumiAdblockNativeRuleBundleError.missingManifest(manifestURL)
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(
            SumiAdblockNativeRuleBundleManifest.self,
            from: data
        )
        guard manifest.schemaVersion == 1 else {
            throw SumiAdblockNativeRuleBundleError.unsupportedSchemaVersion(
                manifest.schemaVersion
            )
        }
        guard manifest.nativeCSSSafetyPolicyVersion
            == SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion
        else {
            throw SumiAdblockNativeRuleBundleError
                .unsupportedNativeCSSSafetyPolicyVersion(
                    manifest.nativeCSSSafetyPolicyVersion
                )
        }
        return SumiAdblockNativeRuleBundle(
            directoryURL: directoryURL,
            manifest: manifest
        )
    }

    func contentRuleListDefinitions(
        from bundle: SumiAdblockNativeRuleBundle,
        including ruleKinds: Set<AdblockCompiledRuleGroupKind> = [.network]
    ) throws -> [SumiContentRuleListDefinition] {
        try bundle.manifest.shards
            .filter { ruleKinds.contains($0.ruleGroupKind) }
            .sorted(by: shardSort)
            .map { shard in
                let data = try verifiedShardData(shard, in: bundle)
                return SumiContentRuleListDefinition(
                    name: shard.webKitIdentifier,
                    encodedContentRuleList: String(
                        decoding: data,
                        as: UTF8.self
                    ),
                    storeIdentifierOverride: shard.webKitIdentifier,
                    contentHashOverride: shard.hash
                )
            }
    }

    func stagedShardURLs(
        from bundle: SumiAdblockNativeRuleBundle,
        including ruleKinds: Set<AdblockCompiledRuleGroupKind> = [
            .network,
            .nativeCosmeticCSS,
        ]
    ) throws -> [String: URL] {
        try Dictionary(
            uniqueKeysWithValues: bundle.manifest.shards
                .filter { ruleKinds.contains($0.ruleGroupKind) }
                .map { shard in
                    _ = try verifiedShardData(shard, in: bundle)
                    return (
                        shardIdentifier(shard),
                        try shardURL(shard, in: bundle)
                    )
                }
        )
    }

    private func verifiedShardData(
        _ shard: SumiAdblockNativeRuleBundleManifest.Shard,
        in bundle: SumiAdblockNativeRuleBundle
    ) throws -> Data {
        let url = try shardURL(shard, in: bundle)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SumiAdblockNativeRuleBundleError.missingShard(
                shard.relativePath
            )
        }
        let data = try Data(contentsOf: url)
        #if DEBUG
            SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
                .recordShardJSONRead(
                    identifier: shard.webKitIdentifier,
                    path: url.path,
                    byteCount: data.count,
                    reason: "prepared native bundle install loaded shard JSON"
                )
        #endif
        guard !data.isEmpty else {
            throw SumiAdblockNativeRuleBundleError.emptyShard(
                shard.relativePath
            )
        }
        guard data.count == shard.byteSize else {
            throw SumiAdblockNativeRuleBundleError.shardSizeMismatch(
                path: shard.relativePath,
                expected: shard.byteSize,
                actual: data.count
            )
        }
        let actualHash = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualHash == shard.hash else {
            throw SumiAdblockNativeRuleBundleError.shardHashMismatch(
                path: shard.relativePath,
                expected: shard.hash,
                actual: actualHash
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              !json.isEmpty
        else {
            throw SumiAdblockNativeRuleBundleError.invalidShardJSON(
                shard.relativePath
            )
        }
        return data
    }

    private func shardURL(
        _ shard: SumiAdblockNativeRuleBundleManifest.Shard,
        in bundle: SumiAdblockNativeRuleBundle
    ) throws -> URL {
        let url = bundle.directoryURL.appendingPathComponent(
            shard.relativePath
        )
        let rootPath = bundle.directoryURL.standardizedFileURL.path
        let shardPath = url.standardizedFileURL.path
        guard shardPath.hasPrefix(rootPath + "/") else {
            throw SumiAdblockNativeRuleBundleError.invalidShardPath(
                shard.relativePath
            )
        }
        return url
    }

    private func shardIdentifier(
        _ shard: SumiAdblockNativeRuleBundleManifest.Shard
    ) -> String {
        URL(fileURLWithPath: shard.relativePath)
            .deletingPathExtension()
            .lastPathComponent
    }

    private func shardSort(
        lhs: SumiAdblockNativeRuleBundleManifest.Shard,
        rhs: SumiAdblockNativeRuleBundleManifest.Shard
    ) -> Bool {
        if lhs.ruleGroupKind == rhs.ruleGroupKind {
            return lhs.relativePath < rhs.relativePath
        }
        return lhs.ruleGroupKind.rawValue < rhs.ruleGroupKind.rawValue
    }
}
