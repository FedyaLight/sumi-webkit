import Foundation

/// Pure projection from the shipped bundle schema into the durable runtime
/// generation schema. It performs no filesystem or WebKit work.
struct SumiAdblockNativeGenerationProjector {
    func compiledManifest(
        from bundleManifest: SumiAdblockNativeRuleBundleManifest,
        previousManifest: AdblockCompiledGenerationManifest?,
        installedDate: Date,
        generationSource: AdblockRuleGenerationSource = .embeddedBundle,
        remoteMetadata: SumiAdblockPreparedBundleRemoteMetadata? = nil
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
        let compiler = NativeContentBlockingCompilerIdentity(
            name: bundleManifest.compiler.name,
            version: bundleManifest.compiler.version
        )
        let sourceLists = bundleManifest.lists.map {
            NativeContentBlockingSourceList(
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
                    manifest: bundleManifest,
                    compiler: compiler
                )
            }
        let nativeCSSShards = bundleManifest.shards
            .filter { $0.ruleGroupKind == .nativeCosmeticCSS }
            .map {
                shardDescriptor(
                    $0,
                    manifest: bundleManifest,
                    compiler: compiler
                )
            }
        let summary = NativeContentBlockingCompilationSummary(
            inputRuleCount: bundleManifest.diagnosticsSummary.inputRuleCount,
            inputByteCount: bundleManifest.lists.reduce(0) {
                $0 + $1.byteSize
            },
            convertedNetworkRuleCount: networkShards.reduce(0) {
                $0 + $1.approximateRuleCount
            },
            convertedNativeCosmeticRuleCount:
                bundleManifest.diagnosticsSummary.nativeCSSRuleCount,
            unsupportedOrIgnoredRuleCount: 0,
            networkJSONByteCount: networkShards.reduce(0) {
                $0 + $1.jsonByteCount
            },
            nativeCosmeticJSONByteCount: nativeCSSShards.reduce(0) {
                $0 + $1.jsonByteCount
            },
            totalJSONByteCount: bundleManifest.shards.reduce(0) {
                $0 + $1.byteSize
            },
            ruleCap: .none
        )

        return AdblockCompiledGenerationManifest(
            schemaVersion: AdblockCompiledGenerationManifest
                .currentSchemaVersion,
            activeGenerationId: bundleManifest.generationId,
            createdDate: generatedDate(bundleManifest) ?? installedDate,
            selectedFilterLists: selectedFilterLists.sorted { $0.id < $1.id },
            networkShards: networkShards,
            nativeCSSShards: nativeCSSShards,
            nativeCompiler: compiler,
            nativeCompilerSourceLists: sourceLists.sorted { $0.id < $1.id },
            nativeLogicalGroups: logicalGroups(bundleManifest),
            nativeCompilationSummary: summary,
            compilerDiagnosticsSummary: diagnosticsSummary(
                bundleManifest,
                generationSource: generationSource
            ),
            lastSuccessfulUpdateDate: installedDate,
            previousGenerationId: previousManifest?.activeGenerationId,
            generationSource: generationSource,
            nativeRuleBundleId: bundleManifest.bundleId,
            bundleProfileId: bundleManifest.profileId,
            remoteMetadata: remoteMetadata
        )
    }

    func diagnosticsSummary(
        _ manifest: SumiAdblockNativeRuleBundleManifest,
        generationSource: AdblockRuleGenerationSource
    ) -> String {
        [
            "generationSource=\(generationSource.rawValue)",
            "bundleId=\(manifest.bundleId)",
            "bundleProfileId=\(manifest.profileId)",
            "nativeCSSSafetyPolicy=\(manifest.nativeCSSSafetyPolicyVersion ?? "missing")",
            "nativeCSSConverted=\(manifest.diagnosticsSummary.nativeCSSRuleCount)",
            "unsafeNativeCSSRootSelectorsFiltered=\(manifest.unsafeCSSFilteredCount)",
            "nativeCSSEmpty=\(manifest.diagnosticsSummary.nativeCSSRuleCount == 0)",
            "rawDuplicatesRemoved=\(manifest.deduplication.rawDuplicateCountRemoved)",
            "nativeJSONDuplicatesRemoved=\(manifest.deduplication.nativeJSONDuplicateCountRemoved)",
            "dedupeSkipped=\(manifest.deduplication.skippedDedupeCount)",
            "networkShards=\(manifest.shards.filter { $0.ruleGroupKind == .network }.count)",
            "nativeCSSShards=\(manifest.shards.filter { $0.ruleGroupKind == .nativeCosmeticCSS }.count)",
            "largestShardBytes=\(manifest.shards.map(\.byteSize).max() ?? 0)",
        ].joined(separator: "; ")
    }

    private func generatedDate(
        _ manifest: SumiAdblockNativeRuleBundleManifest
    ) -> Date? {
        ISO8601DateFormatter().date(from: manifest.generatedDate)
    }

    private func logicalGroups(
        _ manifest: SumiAdblockNativeRuleBundleManifest
    ) -> [NativeContentBlockingLogicalGroupDescriptor]? {
        manifest.groups?.map {
            NativeContentBlockingLogicalGroupDescriptor(
                id: $0.id,
                status: $0.status,
                ruleCount: $0.ruleCount,
                shardCount: $0.shardCount,
                sourceName: $0.source?.sourceName ?? $0.source?.name,
                sourceURL: $0.source?.sourceURL ?? $0.source?.url,
                sourceLicense: $0.source?.sourceLicense ?? $0.source?.license,
                sourceLicenseURL: $0.source?.sourceLicenseURL,
                sourceAttribution: $0.source?.attribution,
                sourceGeneratedAt: $0.source?.generatedAt,
                sourceSha256: $0.source?.sourceSha256,
                sourceNonCommercialOnly: $0.source?.nonCommercialOnly,
                sourceShareAlike: $0.source?.shareAlike,
                sourceGenerator: $0.source?.generator,
                notes: $0.notes ?? []
            )
        }
        .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func shardDescriptor(
        _ shard: SumiAdblockNativeRuleBundleManifest.Shard,
        manifest: SumiAdblockNativeRuleBundleManifest,
        compiler: NativeContentBlockingCompilerIdentity
    ) -> NativeContentBlockingShardDescriptor {
        NativeContentBlockingShardDescriptor(
            id: shardIdentifier(shard),
            generationId: manifest.generationId,
            kind: shard.ruleGroupKind,
            sourceListIdentifiers: manifest.lists.map(\.id).sorted(),
            sourceCategories: Array(Set(manifest.lists.compactMap(\.category)))
                .sorted { $0.rawValue < $1.rawValue },
            protectionGroup: shard.protectionGroupKind(
                bundleProfileId: manifest.profileId
            ),
            webKitIdentifier: shard.webKitIdentifier,
            contentHash: shard.hash,
            approximateRuleCount: shard.ruleCount,
            jsonByteCount: shard.byteSize,
            compilerIdentity: compiler,
            diagnosticsSummary:
                "\(manifest.bundleId);\(shard.logicalGroup ?? shard.group)"
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
