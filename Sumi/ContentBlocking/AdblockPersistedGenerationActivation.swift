import Foundation

@MainActor
final class AdblockPersistedGenerationActivation {
    private let archive: AdblockGenerationArchive
    private let contentBlockingService: SumiContentBlockingService
    private let publisher: AdblockRuleListPublisher
    private let mutationGate: AdblockGenerationMutationGate
    init(
        archive: AdblockGenerationArchive,
        contentBlockingService: SumiContentBlockingService,
        publisher: AdblockRuleListPublisher,
        mutationGate: AdblockGenerationMutationGate
    ) {
        self.archive = archive
        self.contentBlockingService = contentBlockingService
        self.publisher = publisher
        self.mutationGate = mutationGate
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
        } catch {
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
