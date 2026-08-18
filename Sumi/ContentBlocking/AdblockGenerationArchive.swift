import CryptoKit
import Foundation

actor AdblockGenerationArchive {
    private let fileManager: FileManager
    private let paths: AdblockGenerationPaths
    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        paths = AdblockGenerationPaths(
            rootDirectory: rootDirectory
                ?? Self.defaultRootDirectory(fileManager: fileManager)
        )
    }

    nonisolated var storageRoot: URL { paths.rootDirectory }

    nonisolated func advancedArtifactURL(
        generationID: String,
        relativePath: String
    ) throws -> URL {
        try paths.advancedArtifactURL(
            generationId: generationID,
            relativePath: relativePath
        )
    }

    func activeManifest() throws -> AdblockCompiledGenerationManifest? {
        guard let manifest = try decodeManifestIfPresent(at: paths.activeManifestURL) else {
            return nil
        }
        try validateManifestTopology(manifest)
        return manifest
    }

    func archivedManifest(generationId: String) throws -> AdblockCompiledGenerationManifest? {
        try AdblockGenerationPaths.validatePathComponent(generationId, kind: "generation")
        let url = try paths.generationDirectory(generationId)
            .appendingPathComponent("manifest.json")
        guard let manifest = try decodeManifestIfPresent(at: url) else { return nil }
        try validateManifestTopology(manifest)
        guard manifest.activeGenerationId == generationId else {
            throw AdblockUpdateDiagnostics(
                summary: "Archived Adblock generation \(generationId) contains manifest for \(manifest.activeGenerationId)"
            )
        }
        return manifest
    }

    func compiledShardDefinitions(
        for manifest: AdblockCompiledGenerationManifest,
        includingRuleKinds ruleKinds: Set<AdblockCompiledRuleGroupKind> = [.network]
    ) throws -> [SumiContentRuleListDefinition] {
        try validateManifestTopology(manifest)
        return try manifest.networkShards
            .filter { ruleKinds.contains($0.kind) }
            .sorted(by: Self.shardSort)
            .map(shardReader.definition)
    }

    func validateCompiledShardFiles(for manifest: AdblockCompiledGenerationManifest) throws {
        try validateManifestTopology(manifest)
        try manifest.networkShards.forEach(shardReader.validate)
        try validateAdvancedArtifactFiles(for: manifest)
    }

    func commit(
        manifest: AdblockCompiledGenerationManifest,
        stagedCompiledShardURLs: [String: URL],
        stagedAdvancedArtifactURLs: [String: URL] = [:]
    ) throws {
        try validateManifestTopology(manifest)
        let expectedShardIds = Set(manifest.networkShards.map(\.id))
        let suppliedShardIds = Set(stagedCompiledShardURLs.keys)
        guard expectedShardIds == suppliedShardIds else {
            let missing = expectedShardIds.subtracting(suppliedShardIds).sorted()
            let unexpected = suppliedShardIds.subtracting(expectedShardIds).sorted()
            throw AdblockUpdateDiagnostics(
                summary: "Adblock generation staging set mismatch; missing=\(missing.joined(separator: ",")); unexpected=\(unexpected.joined(separator: ","))"
            )
        }
        let expectedArtifactPaths = Set(
            manifest.advancedBlocking?.artifacts.map(\.relativePath) ?? []
        )
        let suppliedArtifactPaths = Set(stagedAdvancedArtifactURLs.keys)
        guard expectedArtifactPaths == suppliedArtifactPaths else {
            let missing = expectedArtifactPaths
                .subtracting(suppliedArtifactPaths).sorted()
            let unexpected = suppliedArtifactPaths
                .subtracting(expectedArtifactPaths).sorted()
            throw AdblockUpdateDiagnostics(
                summary: "Advanced-blocking generation staging set mismatch; missing=\(missing.joined(separator: ",")); unexpected=\(unexpected.joined(separator: ","))"
            )
        }

        try fileManager.createDirectory(at: paths.generatedRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.stagingRoot, withIntermediateDirectories: true)
        let transactionRoot = paths.stagingRoot
            .appendingPathComponent("generation-\(UUID().uuidString)", isDirectory: true)
        let transactionPaths = AdblockGenerationPaths(rootDirectory: transactionRoot)
        let stagedGeneration = try transactionPaths.generationDirectory(manifest.activeGenerationId)
        try fileManager.createDirectory(at: stagedGeneration, withIntermediateDirectories: true)
        defer { removeIfPresent(transactionRoot) }

        for shard in manifest.networkShards.sorted(by: Self.shardSort) {
            guard let source = stagedCompiledShardURLs[shard.id] else {
                throw AdblockUpdateDiagnostics(
                    summary: "Missing staged Adblock shard: \(shard.id)",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
            let destination = try transactionPaths.shardURL(
                generationId: manifest.activeGenerationId,
                shardId: shard.id
            )
            try fileManager.copyItem(at: source, to: destination)
        }

        for artifact in (manifest.advancedBlocking?.artifacts ?? [])
            .sorted(by: { $0.relativePath < $1.relativePath }) {
            guard let source = stagedAdvancedArtifactURLs[artifact.relativePath]
            else {
                throw AdblockUpdateDiagnostics(
                    summary: "Missing staged advanced-blocking artifact: \(artifact.relativePath)"
                )
            }
            let destination = try transactionPaths.advancedArtifactURL(
                generationId: manifest.activeGenerationId,
                relativePath: artifact.relativePath
            )
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
        }

        let stagedReader = makeShardReader(storageRoot: transactionRoot)
        try manifest.networkShards.forEach(stagedReader.validate)
        try validateAdvancedArtifactFiles(
            for: manifest,
            using: transactionPaths
        )
        try encodedManifest(manifest).write(
            to: stagedGeneration.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try publish(stagedGeneration: stagedGeneration, manifest: manifest)
    }

    func replaceActiveManifest(_ manifest: AdblockCompiledGenerationManifest) throws {
        try validateManifestTopology(manifest)
        try atomicWrite(encodedManifest(manifest), to: paths.activeManifestURL)
    }

    func archivedGenerationIds() throws -> [String] {
        guard fileManager.fileExists(atPath: paths.generatedRoot.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: paths.generatedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return url.lastPathComponent
        }
    }

    nonisolated func generationDirectoryURL(generationId: String) throws -> URL {
        try paths.generationDirectory(generationId)
    }

    func stagingDirectoryURL() -> URL {
        paths.stagingRoot
    }

    private var shardReader: AdblockArchivedShardReader {
        makeShardReader(storageRoot: paths.rootDirectory)
    }

    private func makeShardReader(storageRoot: URL) -> AdblockArchivedShardReader {
        AdblockArchivedShardReader(
            storageRoot: storageRoot,
            fileManager: fileManager
        )
    }

    private func publish(
        stagedGeneration: URL,
        manifest: AdblockCompiledGenerationManifest
    ) throws {
        let destination = try paths.generationDirectory(manifest.activeGenerationId)
        let replacedExistingGeneration = fileManager.fileExists(atPath: destination.path)

        if replacedExistingGeneration {
            try ContentBlockingItemExchange.swap(destination, stagedGeneration)
        } else {
            try fileManager.moveItem(at: stagedGeneration, to: destination)
        }

        do {
            try atomicWrite(encodedManifest(manifest), to: paths.activeManifestURL)
        } catch {
            do {
                if replacedExistingGeneration {
                    try ContentBlockingItemExchange.swap(destination, stagedGeneration)
                } else {
                    removeIfPresent(destination)
                }
            } catch let rollbackError {
                throw AdblockUpdateDiagnostics(
                    summary: "Adblock manifest publication failed: \(error.localizedDescription); generation rollback failed: \(rollbackError.localizedDescription)"
                )
            }
            throw error
        }
    }

    private func validateManifestTopology(_ manifest: AdblockCompiledGenerationManifest) throws {
        guard manifest.schemaVersion == AdblockCompiledGenerationManifest.currentSchemaVersion else {
            throw AdblockUpdateDiagnostics(
                summary: "Unsupported persisted Adblock manifest schema: \(manifest.schemaVersion)"
            )
        }
        try AdblockGenerationPaths.validatePathComponent(manifest.activeGenerationId, kind: "generation")
        guard manifest.networkShards.allSatisfy({ $0.kind == .network }) else {
            throw AdblockUpdateDiagnostics(
                summary: "Persisted Adblock shard collection contains a mismatched rule kind"
            )
        }
        let expectedWebKitIdentifiers = manifest.networkShards
            .map(\.webKitIdentifier)
            .sorted()
        guard manifest.webKitRuleListIdentifiers == expectedWebKitIdentifiers else {
            throw AdblockUpdateDiagnostics(
                summary: "Persisted Adblock WebKit identifier index does not match network shards"
            )
        }
        var shardIds = Set<String>()
        var webKitIdentifiers = Set<String>()
        for shard in manifest.networkShards {
            try AdblockGenerationPaths.validatePathComponent(shard.id, kind: "shard")
            guard shard.generationId == manifest.activeGenerationId else {
                throw AdblockUpdateDiagnostics(
                    summary: "Adblock shard \(shard.id) belongs to generation \(shard.generationId), expected \(manifest.activeGenerationId)",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
            guard !shard.webKitIdentifier.isEmpty, shard.jsonByteCount > 0 else {
                throw AdblockUpdateDiagnostics(
                    summary: "Adblock shard \(shard.id) has invalid persisted metadata",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
            guard shardIds.insert(shard.id).inserted else {
                throw AdblockUpdateDiagnostics(summary: "Duplicate Adblock shard identifier: \(shard.id)")
            }
            guard webKitIdentifiers.insert(shard.webKitIdentifier).inserted else {
                throw AdblockUpdateDiagnostics(summary: "Duplicate Adblock WebKit identifier: \(shard.webKitIdentifier)")
            }
        }
        if let advanced = manifest.advancedBlocking {
            guard advanced.format
                    == AdvancedBlockingGenerationDescriptor
                        .safariConverterFormat,
                  advanced.schemaVersion == 1,
                  advanced.runtimeVersion.isEmpty == false,
                  advanced.ruleCount > 0
            else {
                throw AdblockUpdateDiagnostics(
                    summary: "Persisted advanced-blocking generation has incompatible metadata"
                )
            }
            let roles = advanced.artifacts.map(\.role)
            let artifactPaths = advanced.artifacts.map(\.relativePath)
            let requiredRoles: Set<AdvancedBlockingArtifactRole> = [
                .ruleStorage,
                .engineIndex,
                .engineMetadata,
            ]
            guard Set(roles).isSuperset(of: requiredRoles),
                  Set(roles).count == roles.count,
                  Set(artifactPaths).count == artifactPaths.count
            else {
                throw AdblockUpdateDiagnostics(
                    summary: "Persisted advanced-blocking artifact index is incomplete or duplicated"
                )
            }
            for artifact in advanced.artifacts {
                guard artifact.byteSize > 0,
                      artifact.hash.count == 64,
                      artifact.hash.allSatisfy({ $0.isHexDigit })
                else {
                    throw AdblockUpdateDiagnostics(
                        summary: "Persisted advanced-blocking artifact metadata is invalid: \(artifact.relativePath)"
                    )
                }
                _ = try paths.advancedArtifactURL(
                    generationId: manifest.activeGenerationId,
                    relativePath: artifact.relativePath
                )
            }
        }
    }

    private func validateAdvancedArtifactFiles(
        for manifest: AdblockCompiledGenerationManifest,
        using validationPaths: AdblockGenerationPaths? = nil
    ) throws {
        let resolvedPaths = validationPaths ?? paths
        for artifact in manifest.advancedBlocking?.artifacts ?? [] {
            let url = try resolvedPaths.advancedArtifactURL(
                generationId: manifest.activeGenerationId,
                relativePath: artifact.relativePath
            )
            guard fileManager.fileExists(atPath: url.path) else {
                throw AdblockUpdateDiagnostics(
                    summary: "Missing archived advanced-blocking artifact: \(artifact.relativePath)"
                )
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count == artifact.byteSize else {
                throw AdblockUpdateDiagnostics(
                    summary: "Archived advanced-blocking artifact size mismatch: \(artifact.relativePath)"
                )
            }
            let hash = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard hash == artifact.hash.lowercased() else {
                throw AdblockUpdateDiagnostics(
                    summary: "Archived advanced-blocking artifact hash mismatch: \(artifact.relativePath)"
                )
            }
        }
    }

    private func decodeManifestIfPresent(at url: URL) throws -> AdblockCompiledGenerationManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(AdblockCompiledGenerationManifest.self, from: Data(contentsOf: url))
    }

    private func encodedManifest(_ manifest: AdblockCompiledGenerationManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { removeIfPresent(temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            try ContentBlockingItemExchange.swap(url, temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
    }

    private func removeIfPresent(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    private static func shardSort(
        lhs: NativeContentBlockingShardDescriptor,
        rhs: NativeContentBlockingShardDescriptor
    ) -> Bool {
        lhs.kind == rhs.kind ? lhs.id < rhs.id : lhs.kind.rawValue < rhs.kind.rawValue
    }

    private static func defaultRootDirectory(fileManager: FileManager) -> URL {
        let canonical = SumiApplicationSupportDirectory
            .appRootURL(fileManager: fileManager)
            .appendingPathComponent("Adblock", isDirectory: true)
        let legacyBase = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let legacy = legacyBase.appendingPathComponent(
            "Sumi/Adblock",
            isDirectory: true
        )
        return SumiApplicationSupportDirectory.migrateLegacyDirectoryIfNeeded(
            from: legacy,
            to: canonical,
            fileManager: fileManager
        )
    }
}
