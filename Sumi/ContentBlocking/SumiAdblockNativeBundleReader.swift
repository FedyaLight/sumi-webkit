import CryptoKit
import Foundation

/// The filesystem boundary for prepared native rule bundles. All manifest and
/// shard reads pass through the same path, size, hash, and JSON validation.
struct SumiAdblockNativeBundleReader: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
        try validateAdvancedDescriptor(manifest.advancedBlocking)
        return SumiAdblockNativeRuleBundle(
            directoryURL: directoryURL,
            manifest: manifest
        )
    }

    func contentRuleListDefinitions(
        from bundle: SumiAdblockNativeRuleBundle
    ) throws -> [SumiContentRuleListDefinition] {
        try bundle.manifest.shards
            .filter { $0.ruleGroupKind == .network }
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
        from bundle: SumiAdblockNativeRuleBundle
    ) throws -> [String: URL] {
        try Dictionary(
            uniqueKeysWithValues: bundle.manifest.shards
                .filter { $0.ruleGroupKind == .network }
                .map { shard in
                    _ = try verifiedShardData(shard, in: bundle)
                    return (
                        shardIdentifier(shard),
                        try shardURL(shard, in: bundle)
                    )
                }
        )
    }

    func stagedAdvancedArtifactURLs(
        from bundle: SumiAdblockNativeRuleBundle
    ) throws -> [String: URL] {
        guard let descriptor = bundle.manifest.advancedBlocking else {
            return [:]
        }
        return try Dictionary(
            uniqueKeysWithValues: descriptor.artifacts.map { artifact in
                _ = try verifiedAdvancedArtifactData(artifact, in: bundle)
                return (
                    artifact.relativePath,
                    try advancedArtifactURL(artifact, in: bundle)
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

    private func validateAdvancedDescriptor(
        _ descriptor: AdvancedBlockingGenerationDescriptor?
    ) throws {
        guard let descriptor else { return }
        guard descriptor.format
                == AdvancedBlockingGenerationDescriptor.safariConverterFormat,
              descriptor.schemaVersion == 1,
              descriptor.runtimeVersion.isEmpty == false,
              descriptor.ruleCount > 0
        else {
            throw SumiAdblockNativeRuleBundleError.invalidAdvancedDescriptor(
                "unsupported format, schema, runtime version, or empty rule set"
            )
        }

        let requiredRoles: Set<AdvancedBlockingArtifactRole> = [
            .ruleStorage,
            .engineIndex,
            .engineMetadata,
        ]
        let roles = descriptor.artifacts.map(\.role)
        guard Set(roles).isSuperset(of: requiredRoles),
              Set(roles).count == roles.count
        else {
            throw SumiAdblockNativeRuleBundleError.invalidAdvancedDescriptor(
                "required artifact roles are missing or duplicated"
            )
        }
        let paths = descriptor.artifacts.map(\.relativePath)
        guard Set(paths).count == paths.count else {
            throw SumiAdblockNativeRuleBundleError.invalidAdvancedDescriptor(
                "artifact paths are duplicated"
            )
        }

        let requiredPaths: [AdvancedBlockingArtifactRole: String] = [
            .ruleStorage: ".webext/rules.bin",
            .engineIndex: ".webext/engine.bin",
            .engineMetadata: ".webext/meta.bin",
            .sourceRules: ".webext/rules.txt",
            .urlCleaningRules: ".webext/removeparam.json",
            .domainCosmeticRules: ".webext/cosmetic-domains.json",
        ]
        for artifact in descriptor.artifacts {
            guard artifact.byteSize > 0,
                  artifact.hash.count == 64,
                  artifact.hash.allSatisfy({ $0.isHexDigit }),
                  requiredPaths[artifact.role] == artifact.relativePath
            else {
                throw SumiAdblockNativeRuleBundleError.invalidAdvancedDescriptor(
                    "invalid metadata for \(artifact.role.rawValue)"
                )
            }
            _ = try safePayloadURL(
                relativePath: artifact.relativePath,
                in: URL(fileURLWithPath: "/advanced-descriptor-root")
            )
        }
    }

    private func verifiedAdvancedArtifactData(
        _ artifact: AdvancedBlockingGenerationDescriptor.Artifact,
        in bundle: SumiAdblockNativeRuleBundle
    ) throws -> Data {
        let url = try advancedArtifactURL(artifact, in: bundle)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SumiAdblockNativeRuleBundleError.missingAdvancedArtifact(
                artifact.relativePath
            )
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.isEmpty == false else {
            throw SumiAdblockNativeRuleBundleError.emptyAdvancedArtifact(
                artifact.relativePath
            )
        }
        guard data.count == artifact.byteSize else {
            throw SumiAdblockNativeRuleBundleError
                .advancedArtifactSizeMismatch(
                    path: artifact.relativePath,
                    expected: artifact.byteSize,
                    actual: data.count
                )
        }
        let actualHash = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualHash == artifact.hash.lowercased() else {
            throw SumiAdblockNativeRuleBundleError
                .advancedArtifactHashMismatch(
                    path: artifact.relativePath,
                    expected: artifact.hash,
                    actual: actualHash
                )
        }
        return data
    }

    private func advancedArtifactURL(
        _ artifact: AdvancedBlockingGenerationDescriptor.Artifact,
        in bundle: SumiAdblockNativeRuleBundle
    ) throws -> URL {
        do {
            return try safePayloadURL(
                relativePath: artifact.relativePath,
                in: bundle.directoryURL
            )
        } catch {
            throw SumiAdblockNativeRuleBundleError.invalidAdvancedArtifactPath(
                artifact.relativePath
            )
        }
    }

    private func safePayloadURL(
        relativePath: String,
        in root: URL
    ) throws -> URL {
        guard relativePath.isEmpty == false,
              relativePath.hasPrefix("/") == false,
              relativePath.contains("\\") == false,
              relativePath.contains("\0") == false,
              relativePath.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." })
        else {
            throw SumiAdblockNativeRuleBundleError
                .invalidAdvancedArtifactPath(relativePath)
        }
        let standardizedRoot = root.standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath)
            .standardizedFileURL
        guard candidate.path.hasPrefix(standardizedRoot.path + "/") else {
            throw SumiAdblockNativeRuleBundleError
                .invalidAdvancedArtifactPath(relativePath)
        }
        return candidate
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
