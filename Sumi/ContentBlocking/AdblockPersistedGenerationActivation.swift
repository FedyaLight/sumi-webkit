import Foundation

@MainActor
final class AdblockPersistedGenerationActivation {
    private let archive: AdblockGenerationArchive
    private let contentBlockingService: SumiContentBlockingService
    private let publisher: AdblockRuleListPublisher
    private let mutationGate: AdblockGenerationMutationGate
    #if DEBUG
        private let startupDiagnostics: any SumiProtectionStartupRestoreDiagnosticsRecording
    #endif

    init(
        archive: AdblockGenerationArchive,
        contentBlockingService: SumiContentBlockingService,
        publisher: AdblockRuleListPublisher,
        mutationGate: AdblockGenerationMutationGate,
        startupDiagnostics: (any SumiProtectionStartupRestoreDiagnosticsRecording)? = nil
    ) {
        self.archive = archive
        self.contentBlockingService = contentBlockingService
        self.publisher = publisher
        self.mutationGate = mutationGate
        #if DEBUG
            self.startupDiagnostics = startupDiagnostics
                ?? SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
        #else
            _ = startupDiagnostics
        #endif
    }

    func activate(
        _ manifest: AdblockCompiledGenerationManifest,
        lease: AdblockGenerationMutationGate.Lease
    ) async throws {
        guard mutationGate.owns(lease), !Task.isCancelled else { throw CancellationError() }
        try await archive.validateCompiledShardFiles(for: manifest)
        var providerDefinitions = AdblockManifestRuleListProvider.metadataOnlyDefinitions(
            for: manifest
        )
        let preparedUpdate: SumiPreparedContentBlockingUpdate
        do {
            preparedUpdate = try await contentBlockingService.prepareExistingRuleListUpdate(
                ruleLists: providerDefinitions
            )
            #if DEBUG
                startupDiagnostics.recordMetadataOnlyRestoreUsed()
            #endif
        } catch {
            #if DEBUG
                let reason = "Persisted manifest lookup-only restore failed: \(error.localizedDescription)"
                startupDiagnostics.recordFallback(reason: reason)
                startupDiagnostics.recordPayloadBackedRestoreUsed(reason: reason)
                startupDiagnostics.recordRepairCompileUsed(reason: reason)
            #endif
            let definitions = try await archive.compiledShardDefinitions(for: manifest)
            providerDefinitions = definitions.map { $0.metadataOnly() }
            preparedUpdate = try await contentBlockingService.prepareRuleListUpdate(
                ruleLists: definitions,
                retainEncodedRuleListsInPreparedPolicy: false
            )
        }
        guard mutationGate.owns(lease), !Task.isCancelled else { throw CancellationError() }
        publisher.commitPublication(
            PreparedAdblockRuleListPublication(
                manifest: manifest,
                definitions: providerDefinitions,
                preparedContentBlockingUpdate: preparedUpdate
            )
        )
    }
}
