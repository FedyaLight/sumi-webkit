import CryptoKit
import Foundation

struct AdblockArchivedShardReader {
    private let storageRoot: URL
    private let fileManager: FileManager
    init(
        storageRoot: URL,
        fileManager: FileManager = .default
    ) {
        self.storageRoot = storageRoot
        self.fileManager = fileManager
    }

    func definition(for shard: NativeContentBlockingShardDescriptor) throws -> SumiContentRuleListDefinition {
        let data = try validatedData(for: shard)
        return SumiContentRuleListDefinition(
            name: shard.webKitIdentifier,
            encodedContentRuleList: String(decoding: data, as: UTF8.self),
            storeIdentifierOverride: shard.webKitIdentifier,
            contentHashOverride: shard.contentHash
        )
    }

    func validate(_ shard: NativeContentBlockingShardDescriptor) throws {
        _ = try validatedData(for: shard)
    }

    /// Validated shard payload bytes for callers that need the original JSON
    /// (for example, generation migrations).
    func rawValidatedData(
        for shard: NativeContentBlockingShardDescriptor
    ) throws -> Data {
        try validatedData(for: shard)
    }

    private func validatedData(for shard: NativeContentBlockingShardDescriptor) throws -> Data {
        let paths = AdblockGenerationPaths(rootDirectory: storageRoot)
        let url = try paths.shardURL(generationId: shard.generationId, shardId: shard.id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw diagnostics("Missing compiled Adblock shard JSON: \(shard.id)", shard: shard)
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw diagnostics("Missing compiled Adblock shard JSON: \(shard.id)", shard: shard)
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw diagnostics("Empty compiled Adblock shard JSON: \(shard.id)", shard: shard)
        }
        if shard.jsonByteCount > 0, data.count != shard.jsonByteCount {
            throw diagnostics(
                "Compiled Adblock shard size mismatch for \(shard.id): expected \(shard.jsonByteCount), got \(data.count)",
                shard: shard
            )
        }
        if !shard.contentHash.isEmpty {
            let actualHash = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard actualHash.caseInsensitiveCompare(shard.contentHash) == .orderedSame else {
                throw diagnostics(
                    "Compiled Adblock shard hash mismatch for \(shard.id)",
                    shard: shard
                )
            }
        }
        return data
    }

    private func diagnostics(
        _ summary: String,
        shard: NativeContentBlockingShardDescriptor
    ) -> AdblockUpdateDiagnostics {
        AdblockUpdateDiagnostics(
            summary: summary,
            failedShardIdentifier: shard.webKitIdentifier
        )
    }
}
