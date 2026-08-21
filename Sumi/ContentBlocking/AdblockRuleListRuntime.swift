import Foundation
import SumiDomain

/// Live WebKit rule-list runtime. It owns publication state and the lifetime of
/// its serialized generation work; archive and installation algorithms remain
/// separate transaction components.
@MainActor
final class AdblockRuleListRuntime {
    let contentBlockingService: SumiContentBlockingService

    private let generationArchive: AdblockGenerationArchive
    private let advancedBlockingRuntime: SumiAdvancedBlockingRuntime
    private let ruleListProvider: AdblockManifestRuleListProvider
    private let generationInstaller: AdblockGenerationInstaller
    private let persistedGenerationActivation: AdblockPersistedGenerationActivation
    private let generationRetention: AdblockGenerationRetention
    private let cosmeticShardMigration: AdblockCosmeticShardMigration
    private let mutationGate = AdblockGenerationMutationGate()
    private let isRuntimeEnabled: @Sendable () async -> Bool
    private var activeManifestDidChange: (@MainActor () -> Void)?

    var activeManifest: AdblockCompiledGenerationManifest? {
        ruleListProvider.activeManifest
    }

    init(
        isRuntimeEnabled: @escaping @Sendable () async -> Bool = { true },
        generationArchive: AdblockGenerationArchive? = nil,
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler(),
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging
    ) {
        let archive = generationArchive ?? AdblockGenerationArchive()
        let definitionLoader = AdblockManifestRuleListProvider
            .diskBackedDefinitionLoader(storageRoot: archive.storageRoot)

        self.generationArchive = archive
        advancedBlockingRuntime = SumiAdvancedBlockingRuntime(archive: archive)
        self.isRuntimeEnabled = isRuntimeEnabled
        let provider = AdblockManifestRuleListProvider(
            manifest: nil,
            compiledDefinitionLoader: definitionLoader
        )
        ruleListProvider = provider

        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            ruleListProvider: provider,
            compiledRuleListCatalog: compiledRuleListCatalog
        )
        contentBlockingService = service

        let publisher = AdblockRuleListPublisher(
            ruleListProvider: provider,
            contentBlockingService: service
        )
        let retention = AdblockGenerationRetention(
            archive: archive,
            contentRuleListStore: compiler
        )
        generationInstaller = AdblockGenerationInstaller(
            archive: archive,
            publisher: publisher,
            retention: retention,
            mutationGate: mutationGate
        )
        persistedGenerationActivation = AdblockPersistedGenerationActivation(
            archive: archive,
            contentBlockingService: service,
            publisher: publisher,
            mutationGate: mutationGate
        )
        cosmeticShardMigration = AdblockCosmeticShardMigration(archive: archive)
        generationRetention = retention
    }

    #if DEBUG
        func drainStartupTasksForTests(cancel: Bool = false) async {
            await contentBlockingService.drainScheduledTasksForTests(cancel: cancel)
        }
    #endif

    func contentRuleListDefinitions(
        for protectionGroups: Set<SumiProtectionGroupKind>
    ) throws -> [SumiContentRuleListDefinition] {
        try ruleListProvider.persistedDefinitions(for: protectionGroups)
    }

    func advancedConfiguration(
        for document: SumiAdvancedBlockingDocumentContext
    ) async throws -> SumiAdvancedBlockingConfiguration? {
        guard await isRuntimeEnabled(),
              let manifest = activeManifest,
              manifest.advancedBlocking != nil
        else {
            return nil
        }
        return try await advancedBlockingRuntime.configuration(
            for: document,
            in: manifest
        )
    }

    func urlCleaningContribution(
        disabledDomains: [String]
    ) -> SumiURLCleaningContribution? {
        guard let manifest = activeManifest,
              let artifact = manifest.advancedBlocking?.artifacts.first(
                where: { $0.role == .urlCleaningRules }
              ),
              let rulesURL = try? generationArchive.advancedArtifactURL(
                generationID: manifest.activeGenerationId,
                relativePath: artifact.relativePath
              )
        else {
            return nil
        }
        return SumiURLCleaningContribution(
            generationID: manifest.activeGenerationId,
            rulesURL: rulesURL,
            disabledDomains: disabledDomains.sorted()
        )
    }

    func setActiveManifestDidChange(
        _ observer: (@MainActor () -> Void)?
    ) {
        activeManifestDidChange = observer
        if activeManifest != nil {
            observer?()
        }
    }

    func restoreLocalManifestIfAvailable(
        profileId: String
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard await isRuntimeEnabled() else { return nil }
        guard let lease = await mutationGate.acquire() else {
            throw CancellationError()
        }
        defer { mutationGate.release(lease) }
        guard mutationGate.owns(lease), !Task.isCancelled else {
            throw CancellationError()
        }
        guard let manifest = try await generationArchive.activeManifest(),
              manifest.bundleProfileId == profileId
        else {
            return nil
        }
        let effectiveManifest = await cosmeticShardMigration
            .migratedManifestIfPossible(for: manifest)
        try await persistedGenerationActivation.activate(
            effectiveManifest,
            lease: lease
        )
        _ = await generationRetention.removeInactiveGenerations()
        await advancedBlockingRuntime.prepare(for: effectiveManifest)
        activeManifestDidChange?()
        return effectiveManifest
    }

    func installGeneratedBundle(
        at bundleURL: URL,
        profileId: String
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard await isRuntimeEnabled() else { return nil }
        guard let lease = await mutationGate.acquire() else {
            throw CancellationError()
        }
        defer { mutationGate.release(lease) }
        guard mutationGate.owns(lease), !Task.isCancelled else {
            throw CancellationError()
        }
        let manifest = try await generationInstaller.install(
            at: bundleURL,
            profileId: profileId,
            lease: lease
        )
        await advancedBlockingRuntime.deactivate()
        await advancedBlockingRuntime.prepare(for: manifest)
        activeManifestDidChange?()
        return manifest
    }

    func stop() {
        mutationGate.stop()
        contentBlockingService.setPolicy(.disabled)
        contentBlockingService.stopRuntime()
        let advancedBlockingRuntime = advancedBlockingRuntime
        Task {
            await advancedBlockingRuntime.deactivate()
        }
    }
}
