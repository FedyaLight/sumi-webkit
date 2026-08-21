import CryptoKit
import Foundation
import OSLog

/// One-time local upgrade of an installed blocker generation whose WebKit
/// shards still carry domain-scoped cosmetic rules.
///
/// Safari content blockers apply every `css-display-none` selector to every
/// document regardless of its domain trigger, which measurably taxes
/// DOM-heavy pages. Newer generations are built without those rules in the
/// WebKit lists (`SumiSelectedFilterBundleBuilder` routes them into a
/// `cosmetic-domains.json` artifact served by the advanced pipeline); this
/// migration produces the same shape from an already-installed generation
/// without re-downloading any filter list.
///
/// Generations without a supported advanced-blocking half are left untouched:
/// their cosmetic rules would lose their only delivery channel.
actor AdblockCosmeticShardMigration {
    private static let log = Logger.sumi(category: "ContentBlocking")
    private let archive: AdblockGenerationArchive

    init(archive: AdblockGenerationArchive) {
        self.archive = archive
    }

    /// Returns a manifest whose shards no longer carry `if-domain` cosmetic
    /// rules, committing it as the active generation when a rewrite was
    /// needed. Returns the input manifest unchanged when migration is
    /// unnecessary or impossible.
    func migratedManifestIfPossible(
        for manifest: AdblockCompiledGenerationManifest
    ) async -> AdblockCompiledGenerationManifest {
        guard SumiAdvancedBlockingRuntime.supports(manifest.advancedBlocking),
              manifest.advancedBlocking?.artifacts.contains(where: {
                  $0.role == .domainCosmeticRules
              }) != true,
              manifest.networkShards.isEmpty == false
        else {
            return manifest
        }
        do {
            return try await performMigration(for: manifest)
        } catch {
            Self.log.error(
                "Cosmetic shard migration kept the original generation: \(error.localizedDescription, privacy: .public)"
            )
            return manifest
        }
    }

    private func performMigration(
        for manifest: AdblockCompiledGenerationManifest
    ) async throws -> AdblockCompiledGenerationManifest {
        let reader = AdblockArchivedShardReader(storageRoot: archive.storageRoot)
        var migratedId = "\(manifest.activeGenerationId)-c1"
        var stagedShards = [String: URL]()
        var migratedShards = [NativeContentBlockingShardDescriptor]()
        var extractedCosmetics = [AdblockCosmeticDomainIndex.Entry]()

        let transactionRoot = await archive.stagingDirectoryURL()
            .appendingPathComponent("cosmetic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: transactionRoot,
            withIntermediateDirectories: true
        )
        defer {
            do {
                try FileManager.default.removeItem(at: transactionRoot)
            } catch {
                Self.log.error(
                    "Could not remove cosmetic migration staging directory: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        for shard in manifest.networkShards.sorted(by: { $0.id < $1.id }) {
            let originalData = try reader.validatedData(for: shard)
            guard let rules = try JSONSerialization.jsonObject(with: originalData)
                as? [[String: Any]]
            else {
                throw AdblockUpdateDiagnostics(
                    summary: "Migrated shard payload is not a rule array"
                )
            }
            let split = AdblockCosmeticDomainIndex.splitRules(rules)
            extractedCosmetics.append(contentsOf: split.cosmetics)
            guard split.network.isEmpty == false else { continue }
            let networkData = try JSONSerialization.data(withJSONObject: split.network)
            let stagedURL = transactionRoot.appendingPathComponent(
                "\(shard.id).json"
            )
            try networkData.write(to: stagedURL, options: .atomic)
            stagedShards[shard.id] = stagedURL
            migratedShards.append(Self.migratedDescriptor(
                shard,
                generationId: migratedId,
                payload: networkData,
                ruleCount: split.network.count
            ))
        }

        if extractedCosmetics.isEmpty {
            // Add only the marker artifact. Reuse the current generation and
            // identifiers because none of the WebKit payloads changed.
            migratedId = manifest.activeGenerationId
            migratedShards = manifest.networkShards
            stagedShards = try Dictionary(
                uniqueKeysWithValues: manifest.networkShards.map { shard in
                    (
                        shard.id,
                        try AdblockGenerationPaths(rootDirectory: archive.storageRoot)
                            .shardURL(
                                generationId: manifest.activeGenerationId,
                                shardId: shard.id
                            )
                    )
                }
            )
        }

        if migratedShards.isEmpty {
            let placeholderData = Data(
                "[{\"action\":{\"type\":\"block\"},\"trigger\":{\"url-filter\":\"^$\"}}]\n".utf8
            )
            let shard = manifest.networkShards[0]
            let stagedURL = transactionRoot.appendingPathComponent(
                "\(shard.id).json"
            )
            try placeholderData.write(to: stagedURL, options: .atomic)
            stagedShards[shard.id] = stagedURL
            migratedShards.append(Self.migratedDescriptor(
                shard,
                generationId: migratedId,
                payload: placeholderData,
                ruleCount: 0
            ))
        }

        let cosmeticData = try AdblockCosmeticDomainIndex.artifactData(
            for: extractedCosmetics
        )
        var migratedManifest = AdblockCompiledGenerationManifest(
            schemaVersion: manifest.schemaVersion,
            activeGenerationId: migratedId,
            selectedFilterLists: manifest.selectedFilterLists,
            networkShards: migratedShards,
            advancedBlocking: Self.migratedAdvancedDescriptor(
                manifest.advancedBlocking,
                cosmeticData: cosmeticData
            ),
            lastSuccessfulUpdateDate: manifest.lastSuccessfulUpdateDate,
            bundleProfileId: manifest.bundleProfileId
        )

        var stagedAdvancedArtifacts = [String: URL]()
        for artifact in manifest.advancedBlocking?.artifacts ?? [] {
            stagedAdvancedArtifacts[artifact.relativePath] = try archive
                .advancedArtifactURL(
                    generationID: manifest.activeGenerationId,
                    relativePath: artifact.relativePath
                )
        }
        let cosmeticStagingURL = transactionRoot.appendingPathComponent(
            "cosmetic-domains.json"
        )
        try cosmeticData.write(to: cosmeticStagingURL, options: .atomic)
        stagedAdvancedArtifacts[AdblockCosmeticDomainIndex.artifactRelativePath] =
            cosmeticStagingURL

        try await archive.commit(
            manifest: migratedManifest,
            stagedCompiledShardURLs: stagedShards,
            stagedAdvancedArtifactURLs: stagedAdvancedArtifacts
        )

        if let committed = try await archive.activeManifest(),
           committed.activeGenerationId == migratedId {
            migratedManifest = committed
        }
        return migratedManifest
    }

    private static func migratedDescriptor(
        _ shard: NativeContentBlockingShardDescriptor,
        generationId: String,
        payload: Data,
        ruleCount: Int
    ) -> NativeContentBlockingShardDescriptor {
        let digest = SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
        return NativeContentBlockingShardDescriptor(
            id: shard.id,
            generationId: generationId,
            kind: shard.kind,
            protectionGroup: shard.protectionGroup,
            webKitIdentifier: "\(shard.webKitIdentifier).c1",
            contentHash: digest,
            approximateRuleCount: ruleCount,
            jsonByteCount: payload.count
        )
    }

    private static func migratedAdvancedDescriptor(
        _ descriptor: AdvancedBlockingGenerationDescriptor?,
        cosmeticData: Data
    ) -> AdvancedBlockingGenerationDescriptor? {
        guard let descriptor else { return nil }
        let artifact = AdvancedBlockingGenerationDescriptor.Artifact(
            role: .domainCosmeticRules,
            relativePath: AdblockCosmeticDomainIndex.artifactRelativePath,
            hash: SHA256.hash(data: cosmeticData)
                .map { String(format: "%02x", $0) }
                .joined(),
            byteSize: cosmeticData.count
        )
        return AdvancedBlockingGenerationDescriptor(
            format: descriptor.format,
            schemaVersion: descriptor.schemaVersion,
            runtimeVersion: descriptor.runtimeVersion,
            ruleCount: descriptor.ruleCount,
            artifacts: descriptor.artifacts + [artifact]
        )
    }
}
