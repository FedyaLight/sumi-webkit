import Foundation

struct PreparedAdblockRuleListPublication {
    let manifest: AdblockCompiledGenerationManifest
    let definitions: [SumiContentRuleListDefinition]
    let preparedContentBlockingUpdate: SumiPreparedContentBlockingUpdate
}

@MainActor
final class AdblockRuleListPublisher {
    private let ruleListProvider: AdblockManifestRuleListProvider
    private let contentBlockingService: SumiContentBlockingService

    init(
        ruleListProvider: AdblockManifestRuleListProvider,
        contentBlockingService: SumiContentBlockingService
    ) {
        self.ruleListProvider = ruleListProvider
        self.contentBlockingService = contentBlockingService
    }

    func preparePublication(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws -> PreparedAdblockRuleListPublication {
        let prepared = try await contentBlockingService.prepareRuleListUpdate(
            ruleLists: definitions,
            retainEncodedRuleListsInPreparedPolicy: false
        )
        return PreparedAdblockRuleListPublication(
            manifest: manifest,
            definitions: definitions.map { $0.metadataOnly() },
            preparedContentBlockingUpdate: prepared
        )
    }

    func commitPublication(_ publication: PreparedAdblockRuleListPublication) {
        let stagedContentPublication = contentBlockingService.stagePreparedContentBlockingUpdate(
            publication.preparedContentBlockingUpdate
        )
        // Both states are installed before either observable update is sent.
        // Provider observers see the staged WebKit policy; WebKit-update
        // observers run only after the provider exposes the same manifest.
        ruleListProvider.updateManifest(
            publication.manifest,
            compiledDefinitions: publication.definitions
        )
        if let stagedContentPublication {
            contentBlockingService.publishStagedContentBlockingUpdate(
                stagedContentPublication
            )
        }
    }
}
