import Foundation

/// Pure projection from the shipped bundle schema into the durable runtime
/// generation schema. It performs no filesystem or WebKit work.
struct SumiAdblockNativeGenerationProjector {
    func compiledManifest(
        from bundleManifest: SumiAdblockNativeRuleBundleManifest,
        previousManifest: AdblockCompiledGenerationManifest?,
        installedDate: Date
    ) -> AdblockCompiledGenerationManifest {
        let selectedFilterLists = bundleManifest.lists.map {
            AdblockCompiledGenerationManifest.SelectedFilterList(
                id: $0.id,
                displayName: $0.displayName,
                contentHash: $0.hash,
                category: $0.category,
                inputByteCount: $0.byteSize,
                approximateRuleCount: $0.ruleCount
            )
        }
        let networkShards = bundleManifest.shards
            .filter { $0.ruleGroupKind == .network }
            .map {
                shardDescriptor(
                    $0,
                    manifest: bundleManifest
                )
            }
        let previousGenerationId = if previousManifest?.activeGenerationId
            == bundleManifest.generationId {
            previousManifest?.previousGenerationId
        } else {
            previousManifest?.activeGenerationId
        }

        return AdblockCompiledGenerationManifest(
            schemaVersion: AdblockCompiledGenerationManifest
                .currentSchemaVersion,
            activeGenerationId: bundleManifest.generationId,
            selectedFilterLists: selectedFilterLists.sorted { $0.id < $1.id },
            networkShards: networkShards,
            advancedBlocking: bundleManifest.advancedBlocking,
            lastSuccessfulUpdateDate: installedDate,
            previousGenerationId: previousGenerationId,
            bundleProfileId: bundleManifest.profileId
        )
    }

    private func shardDescriptor(
        _ shard: SumiAdblockNativeRuleBundleManifest.Shard,
        manifest: SumiAdblockNativeRuleBundleManifest
    ) -> NativeContentBlockingShardDescriptor {
        NativeContentBlockingShardDescriptor(
            id: shardIdentifier(shard),
            generationId: manifest.generationId,
            kind: shard.ruleGroupKind,
            protectionGroup: shard.protectionGroupKind(
                bundleProfileId: manifest.profileId
            ),
            webKitIdentifier: shard.webKitIdentifier,
            contentHash: shard.hash,
            approximateRuleCount: shard.ruleCount,
            jsonByteCount: shard.byteSize
        )
    }

    private func shardIdentifier(
        _ shard: SumiAdblockNativeRuleBundleManifest.Shard
    ) -> String {
        URL(fileURLWithPath: shard.relativePath)
            .deletingPathExtension()
            .lastPathComponent
    }
}
