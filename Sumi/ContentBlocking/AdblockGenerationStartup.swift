import Foundation

/// Performs the single serialized startup transaction for persisted Adblock state.
/// Task lifetime remains with `AdblockRuleListRuntime`, which can cancel the work
/// when the protection runtime transitions to Off.
@MainActor
final class AdblockGenerationStartup {
    private let archive: AdblockGenerationArchive
    private let ruleListProvider: AdblockManifestRuleListProvider
    private let recovery: AdblockGenerationRecovery
    private let retention: AdblockGenerationRetention
    private let preparedBundleInstaller: AdblockPreparedBundleInstaller
    private let mutationGate: AdblockGenerationMutationGate
    private let isRuntimeEnabled: @Sendable () async -> Bool
    private let embeddedBundleURLProvider: @MainActor () -> URL?
    #if DEBUG
        private let diagnostics: any SumiProtectionStartupRestoreDiagnosticsRecording
    #endif

    init(
        archive: AdblockGenerationArchive,
        ruleListProvider: AdblockManifestRuleListProvider,
        recovery: AdblockGenerationRecovery,
        retention: AdblockGenerationRetention,
        preparedBundleInstaller: AdblockPreparedBundleInstaller,
        mutationGate: AdblockGenerationMutationGate,
        isRuntimeEnabled: @escaping @Sendable () async -> Bool,
        embeddedBundleURLProvider: @escaping @MainActor () -> URL?,
        diagnostics: (any SumiProtectionStartupRestoreDiagnosticsRecording)? = nil
    ) {
        self.archive = archive
        self.ruleListProvider = ruleListProvider
        self.recovery = recovery
        self.retention = retention
        self.preparedBundleInstaller = preparedBundleInstaller
        self.mutationGate = mutationGate
        self.isRuntimeEnabled = isRuntimeEnabled
        self.embeddedBundleURLProvider = embeddedBundleURLProvider
        #if DEBUG
            self.diagnostics = diagnostics
                ?? SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
        #else
            _ = diagnostics
        #endif
    }

    func run(lease: AdblockGenerationMutationGate.Lease) async {
        await loadActiveManifestIfEnabled(lease: lease)
        guard mutationGate.owns(lease), !Task.isCancelled else { return }
        _ = await recovery.restorePreviousGenerationIfNeeded()
        guard mutationGate.owns(lease), !Task.isCancelled else { return }
        _ = await retention.removeUnrecoverableGenerations()
    }

    private func loadActiveManifestIfEnabled(
        lease: AdblockGenerationMutationGate.Lease
    ) async {
        guard mutationGate.owns(lease),
              !Task.isCancelled,
              await isRuntimeEnabled()
        else { return }

        let observedManifest = ruleListProvider.activeManifest
        do {
            let manifest = try await archive.activeManifest()
            guard mutationGate.owns(lease), !Task.isCancelled else { return }
            #if DEBUG
                diagnostics.recordManifest(manifest)
            #endif

            do {
                if try await preparedBundleInstaller.installEmbeddedBundleIfNeeded(
                    at: embeddedBundleURLProvider(),
                    previousManifest: manifest,
                    lease: lease
                ) != nil { return }
            } catch is CancellationError {
                return
            } catch {
                guard let manifest else { throw error }
                try await archive.validateCompiledShardFiles(for: manifest)
                guard mutationGate.owns(lease), !Task.isCancelled else { return }
                updateManifestIfNoNewerPublication(
                    manifest,
                    replacing: observedManifest,
                    compiledDefinitions: AdblockManifestRuleListProvider
                        .metadataOnlyDefinitions(for: manifest)
                )
                return
            }

            if let manifest {
                try await archive.validateCompiledShardFiles(for: manifest)
            }
            guard mutationGate.owns(lease), !Task.isCancelled else { return }
            updateManifestIfNoNewerPublication(
                manifest,
                replacing: observedManifest,
                compiledDefinitions: manifest.map {
                    AdblockManifestRuleListProvider.metadataOnlyDefinitions(for: $0)
                } ?? []
            )
        } catch is CancellationError {
            return
        } catch {
            guard mutationGate.owns(lease) else { return }
            updateManifestIfNoNewerPublication(nil, replacing: observedManifest)
        }
    }

    private func updateManifestIfNoNewerPublication(
        _ manifest: AdblockCompiledGenerationManifest?,
        replacing observedManifest: AdblockCompiledGenerationManifest?,
        compiledDefinitions: [SumiContentRuleListDefinition] = []
    ) {
        guard ruleListProvider.activeManifest == observedManifest else { return }
        ruleListProvider.updateManifest(
            manifest,
            compiledDefinitions: compiledDefinitions
        )
    }
}
