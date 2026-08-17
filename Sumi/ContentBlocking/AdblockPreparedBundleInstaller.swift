import Foundation

@MainActor
final class AdblockGenerationInstaller {
    private let archive: AdblockGenerationArchive
    private let bundleReader: SumiAdblockNativeBundleReader
    private let generationProjector: SumiAdblockNativeGenerationProjector
    private let publisher: AdblockRuleListPublisher
    private let retention: AdblockGenerationRetention
    private let mutationGate: AdblockGenerationMutationGate
    init(
        archive: AdblockGenerationArchive,
        publisher: AdblockRuleListPublisher,
        retention: AdblockGenerationRetention,
        mutationGate: AdblockGenerationMutationGate,
        bundleReader: SumiAdblockNativeBundleReader =
            SumiAdblockNativeBundleReader(),
        generationProjector: SumiAdblockNativeGenerationProjector =
            SumiAdblockNativeGenerationProjector()
    ) {
        self.archive = archive
        self.bundleReader = bundleReader
        self.generationProjector = generationProjector
        self.publisher = publisher
        self.retention = retention
        self.mutationGate = mutationGate
    }

    func install(
        at bundleURL: URL,
        profileId: String,
        previousManifest: AdblockCompiledGenerationManifest?,
        lease: AdblockGenerationMutationGate.Lease
    ) async throws -> AdblockCompiledGenerationManifest {
        let bundle = try loadBundle(
            at: bundleURL,
            profileId: profileId
        )
        return try await publish(
            bundle,
            at: bundleURL,
            profileId: profileId,
            previousManifest: previousManifest,
            lease: lease
        )
    }

    private func publish(
        _ bundle: SumiAdblockNativeRuleBundle,
        at bundleURL: URL,
        profileId: String,
        previousManifest: AdblockCompiledGenerationManifest?,
        lease: AdblockGenerationMutationGate.Lease
    ) async throws -> AdblockCompiledGenerationManifest {
        guard mutationGate.owns(lease), !Task.isCancelled else { throw CancellationError() }
        let manifest = generationProjector.compiledManifest(
            from: bundle.manifest,
            previousManifest: previousManifest,
            installedDate: Date()
        )
        let definitions = try bundleReader.contentRuleListDefinitions(
            from: bundle
        )
        let publication = try await publisher.preparePublication(
            manifest: manifest,
            definitions: definitions
        )
        guard mutationGate.owns(lease), !Task.isCancelled else { throw CancellationError() }
        let stagedShardURLs = try bundleReader.stagedShardURLs(from: bundle)
        let stagedAdvancedArtifactURLs = try bundleReader
            .stagedAdvancedArtifactURLs(from: bundle)
        do {
            try await archive.commit(
                manifest: manifest,
                stagedCompiledShardURLs: stagedShardURLs,
                stagedAdvancedArtifactURLs: stagedAdvancedArtifactURLs
            )
        } catch {
            throw AdblockUpdateDiagnostics(
                summary: "Adblock bundle manifest commit failed: \(error.localizedDescription)",
                stage: .manifestCommit,
                bundleProfileId: bundle.manifest.profileId,
                bundlePath: bundleURL.path
            )
        }

        // Once the durable pointer changes, runtime publication must complete
        // even if the module was disabled while the archive actor was running.
        publisher.commitPublication(publication)
        if mutationGate.owns(lease), !Task.isCancelled {
            _ = await retention.removeUnrecoverableGenerations()
        }
        return manifest
    }

    private func loadBundle(
        at bundleURL: URL,
        profileId: String
    ) throws -> SumiAdblockNativeRuleBundle {
        do {
            let bundle = try bundleReader.load(from: bundleURL)
            guard bundle.manifest.profileId == profileId else {
                throw AdblockUpdateDiagnostics(
                    summary: "Adblock generation profile \(bundle.manifest.profileId) does not match requested profile \(profileId)",
                    stage: .manifestRead,
                    bundleProfileId: profileId,
                    bundlePath: bundleURL.path
                )
            }
            return bundle
        } catch {
            if let diagnostics = error as? AdblockUpdateDiagnostics {
                throw diagnostics
            }
            throw diagnostics(
                summary: "Adblock bundle install failed before publish: \(error.localizedDescription)",
                stage: Self.bundleLoadFailureStage(error),
                profileId: profileId,
                bundleURL: bundleURL,
                error: error
            )
        }
    }

    private func diagnostics(
        summary: String,
        stage: AdblockUpdateFailureStage,
        profileId: String,
        bundleURL: URL,
        error: Error
    ) -> AdblockUpdateDiagnostics {
        AdblockUpdateDiagnostics(
            summary: "\(summary); bundleProfileId=\(profileId); bundlePath=\(bundleURL.path); details=\(error.localizedDescription)",
            stage: stage,
            bundleProfileId: profileId,
            bundlePath: bundleURL.path
        )
    }

    private static func bundleLoadFailureStage(_ error: Error) -> AdblockUpdateFailureStage {
        guard let error = error as? SumiAdblockNativeRuleBundleError else {
            return .manifestRead
        }
        switch error {
        case .missingManifest,
             .unsupportedSchemaVersion,
             .invalidAdvancedDescriptor:
            return .manifestRead
        case .missingShard,
             .emptyShard,
             .invalidShardPath,
             .missingAdvancedArtifact,
             .emptyAdvancedArtifact,
             .invalidAdvancedArtifactPath:
            return .missingShard
        case .shardHashMismatch,
             .shardSizeMismatch,
             .advancedArtifactHashMismatch,
             .advancedArtifactSizeMismatch:
            return .hashVerification
        case .invalidShardJSON:
            return .jsonParse
        }
    }
}
