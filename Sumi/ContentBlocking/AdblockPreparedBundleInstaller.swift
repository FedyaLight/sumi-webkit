import Foundation

@MainActor
final class AdblockPreparedBundleInstaller {
    private let archive: AdblockGenerationArchive
    private let bundleReader: SumiAdblockNativeBundleReader
    private let generationProjector: SumiAdblockNativeGenerationProjector
    private let publisher: AdblockRuleListPublisher
    private let retention: AdblockGenerationRetention
    private let mutationGate: AdblockGenerationMutationGate
    #if DEBUG
        private let startupDiagnostics: any SumiProtectionStartupRestoreDiagnosticsRecording
    #endif

    init(
        archive: AdblockGenerationArchive,
        publisher: AdblockRuleListPublisher,
        retention: AdblockGenerationRetention,
        mutationGate: AdblockGenerationMutationGate,
        bundleReader: SumiAdblockNativeBundleReader =
            SumiAdblockNativeBundleReader(),
        generationProjector: SumiAdblockNativeGenerationProjector =
            SumiAdblockNativeGenerationProjector(),
        startupDiagnostics: (any SumiProtectionStartupRestoreDiagnosticsRecording)? = nil
    ) {
        self.archive = archive
        self.bundleReader = bundleReader
        self.generationProjector = generationProjector
        self.publisher = publisher
        self.retention = retention
        self.mutationGate = mutationGate
        #if DEBUG
            self.startupDiagnostics = startupDiagnostics
                ?? SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
        #else
            _ = startupDiagnostics
        #endif
    }

    func installEmbeddedBundleIfNeeded(
        at bundleURL: URL?,
        previousManifest: AdblockCompiledGenerationManifest?,
        lease: AdblockGenerationMutationGate.Lease
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard let bundleURL else { return nil }
        let bundle = try loadBundle(
            at: bundleURL,
            source: .appResource,
            profileId: SumiProtectionBundleProfile.adblock
        )
        guard shouldInstallEmbeddedBundle(bundle, previousManifest: previousManifest) else {
            return nil
        }
        return try await publish(
            bundle,
            at: bundleURL,
            source: .appResource,
            profileId: SumiProtectionBundleProfile.adblock,
            previousManifest: previousManifest,
            remoteMetadata: nil,
            lease: lease
        )
    }

    func install(
        at bundleURL: URL,
        source: SumiAdblockBundleInstallSource,
        profileId: String,
        previousManifest: AdblockCompiledGenerationManifest?,
        remoteMetadata: SumiAdblockPreparedBundleRemoteMetadata?,
        lease: AdblockGenerationMutationGate.Lease
    ) async throws -> AdblockCompiledGenerationManifest {
        let bundle = try loadBundle(
            at: bundleURL,
            source: source,
            profileId: profileId
        )
        return try await publish(
            bundle,
            at: bundleURL,
            source: source,
            profileId: profileId,
            previousManifest: previousManifest,
            remoteMetadata: remoteMetadata,
            lease: lease
        )
    }

    private func publish(
        _ bundle: SumiAdblockNativeRuleBundle,
        at bundleURL: URL,
        source: SumiAdblockBundleInstallSource,
        profileId: String,
        previousManifest: AdblockCompiledGenerationManifest?,
        remoteMetadata: SumiAdblockPreparedBundleRemoteMetadata?,
        lease: AdblockGenerationMutationGate.Lease
    ) async throws -> AdblockCompiledGenerationManifest {
        guard mutationGate.owns(lease), !Task.isCancelled else { throw CancellationError() }
        #if DEBUG
            let installReason = "Installing prepared bundle \(bundle.manifest.bundleId) from \(source.generationSource.rawValue)"
            startupDiagnostics.recordGenerationStaleCheck(
                consideredStale: true,
                reason: installReason
            )
            startupDiagnostics.recordPayloadBackedRestoreUsed(reason: installReason)
            startupDiagnostics.recordRepairCompileUsed(reason: installReason)
        #endif
        let manifest = generationProjector.compiledManifest(
            from: bundle.manifest,
            previousManifest: previousManifest,
            installedDate: Date(),
            generationSource: source.generationSource,
            remoteMetadata: remoteMetadata
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
        do {
            try await archive.commit(
                manifest: manifest,
                stagedCompiledShardURLs: stagedShardURLs
            )
        } catch {
            throw AdblockUpdateDiagnostics(
                summary: "Adblock bundle manifest commit failed: \(error.localizedDescription)",
                stage: .embeddedBundleManifestCommit,
                generationSource: source.generationSource,
                bundleProfileId: bundle.manifest.profileId,
                bundlePath: bundleURL.path,
                nativeRuleBundleId: bundle.manifest.bundleId
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
        source: SumiAdblockBundleInstallSource,
        profileId: String
    ) throws -> SumiAdblockNativeRuleBundle {
        do {
            let bundle = try bundleReader.load(from: bundleURL)
            guard bundle.manifest.profileId == profileId else {
                throw AdblockUpdateDiagnostics(
                    summary: "Prepared Adblock bundle profile \(bundle.manifest.profileId) does not match requested profile \(profileId)",
                    stage: .embeddedBundleManifestRead,
                    generationSource: source.generationSource,
                    bundleProfileId: profileId,
                    bundlePath: bundleURL.path,
                    nativeRuleBundleId: bundle.manifest.bundleId
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
                source: source,
                profileId: profileId,
                bundleURL: bundleURL,
                error: error
            )
        }
    }

    private func shouldInstallEmbeddedBundle(
        _ bundle: SumiAdblockNativeRuleBundle,
        previousManifest: AdblockCompiledGenerationManifest?
    ) -> Bool {
        guard let previousManifest else {
            #if DEBUG
                startupDiagnostics.recordGenerationStaleCheck(
                    consideredStale: true,
                    reason: "No active prepared manifest; embedded bundle \(bundle.manifest.bundleId) can seed startup"
                )
            #endif
            return true
        }
        guard previousManifest.generationSource == .embeddedBundle else {
            #if DEBUG
                startupDiagnostics.recordGenerationStaleCheck(
                    consideredStale: false,
                    reason: "Active \(previousManifest.generationSource.rawValue) generation is preserved; embedded bundle is not a startup repair candidate"
                )
            #endif
            return false
        }
        let shouldInstall = previousManifest.nativeRuleBundleId != bundle.manifest.bundleId
        #if DEBUG
            startupDiagnostics.recordGenerationStaleCheck(
                consideredStale: shouldInstall,
                reason: shouldInstall
                    ? "Embedded bundle changed from \(previousManifest.nativeRuleBundleId ?? "nil") to \(bundle.manifest.bundleId)"
                    : "Embedded bundle \(bundle.manifest.bundleId) already matches active generation"
            )
        #endif
        return shouldInstall
    }

    private func diagnostics(
        summary: String,
        stage: AdblockUpdateFailureStage,
        source: SumiAdblockBundleInstallSource,
        profileId: String,
        bundleURL: URL,
        error: Error
    ) -> AdblockUpdateDiagnostics {
        AdblockUpdateDiagnostics(
            summary: "\(summary); bundleSource=\(source.rawValue); bundleProfileId=\(profileId); bundlePath=\(bundleURL.path); details=\(error.localizedDescription)",
            stage: stage,
            generationSource: source.generationSource,
            bundleProfileId: profileId,
            bundlePath: bundleURL.path
        )
    }

    private static func bundleLoadFailureStage(_ error: Error) -> AdblockUpdateFailureStage {
        guard let error = error as? SumiAdblockNativeRuleBundleError else {
            return .embeddedBundleManifestRead
        }
        switch error {
        case .missingManifest,
             .unsupportedSchemaVersion,
             .unsupportedNativeCSSSafetyPolicyVersion,
             .manifestChangedDuringValidation:
            return .embeddedBundleManifestRead
        case .missingShard, .emptyShard, .invalidShardPath:
            return .embeddedBundleMissingShard
        case .shardHashMismatch, .shardSizeMismatch:
            return .embeddedBundleHashVerification
        case .invalidShardJSON:
            return .embeddedBundleJSONParse
        }
    }
}
