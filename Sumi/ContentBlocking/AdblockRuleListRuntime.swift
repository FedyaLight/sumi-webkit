import Foundation
import SumiDomain

/// Live WebKit rule-list runtime. It owns publication state and the lifetime of
/// its serialized generation work; archive/install/recovery algorithms remain
/// separate transaction components.
@MainActor
final class AdblockRuleListRuntime {
    let contentBlockingService: SumiContentBlockingService

    private let generationArchive: AdblockGenerationArchive
    private let ruleListProvider: AdblockManifestRuleListProvider
    private let preparedBundleInstaller: AdblockPreparedBundleInstaller
    private let persistedGenerationActivation: AdblockPersistedGenerationActivation
    private let mutationGate = AdblockGenerationMutationGate()
    private let isRuntimeEnabled: @Sendable () async -> Bool
    private let startup: AdblockGenerationStartup
    #if DEBUG
        private let startupDiagnostics: any SumiProtectionStartupRestoreDiagnosticsRecording
    #endif
    private var startupTask: Task<Void, Never>?

    var activeManifest: AdblockCompiledGenerationManifest? {
        ruleListProvider.activeManifest
    }

    init(
        isRuntimeEnabled: @escaping @Sendable () async -> Bool = { true },
        generationArchive: AdblockGenerationArchive? = nil,
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler(),
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        embeddedBundleURLProvider: @escaping @MainActor () -> URL? = {
            SumiAdblockNativeBundleReader().bundledDirectoryURL(
                for: SumiProtectionBundleProfile.adblock
            )
        },
        startupDiagnostics: (any SumiProtectionStartupRestoreDiagnosticsRecording)? = nil
    ) {
        #if DEBUG
            let diagnostics = startupDiagnostics
                ?? SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
            self.startupDiagnostics = diagnostics
            let archive = generationArchive ?? AdblockGenerationArchive(
                startupDiagnostics: diagnostics
            )
            let definitionLoader = AdblockManifestRuleListProvider
                .diskBackedDefinitionLoader(
                    storageRoot: archive.storageRoot,
                    startupDiagnostics: diagnostics
                )
        #else
            _ = startupDiagnostics
            let archive = generationArchive ?? AdblockGenerationArchive()
            let definitionLoader = AdblockManifestRuleListProvider
                .diskBackedDefinitionLoader(storageRoot: archive.storageRoot)
        #endif

        self.generationArchive = archive
        self.isRuntimeEnabled = isRuntimeEnabled
        let provider = AdblockManifestRuleListProvider(
            manifest: nil,
            compiledDefinitionLoader: definitionLoader
        )
        ruleListProvider = provider

        #if DEBUG
            let service = SumiContentBlockingService(
                policy: .disabled,
                compiler: compiler,
                ruleListProvider: provider,
                compiledRuleListCatalog: compiledRuleListCatalog,
                startupDiagnostics: diagnostics
            )
        #else
            let service = SumiContentBlockingService(
                policy: .disabled,
                compiler: compiler,
                ruleListProvider: provider,
                compiledRuleListCatalog: compiledRuleListCatalog
            )
        #endif
        contentBlockingService = service

        let publisher = AdblockRuleListPublisher(
            ruleListProvider: provider,
            contentBlockingService: service
        )
        #if DEBUG
            let retention = AdblockGenerationRetention(
                archive: archive,
                contentRuleListStore: compiler,
                startupDiagnostics: diagnostics
            )
            let recovery = AdblockGenerationRecovery(
                archive: archive,
                publisher: publisher,
                contentRuleListStore: compiler,
                startupDiagnostics: diagnostics
            )
            let installer = AdblockPreparedBundleInstaller(
                archive: archive,
                publisher: publisher,
                retention: retention,
                mutationGate: mutationGate,
                startupDiagnostics: diagnostics
            )
            let activation = AdblockPersistedGenerationActivation(
                archive: archive,
                contentBlockingService: service,
                publisher: publisher,
                mutationGate: mutationGate,
                startupDiagnostics: diagnostics
            )
            let startup = AdblockGenerationStartup(
                archive: archive,
                ruleListProvider: provider,
                recovery: recovery,
                retention: retention,
                preparedBundleInstaller: installer,
                mutationGate: mutationGate,
                isRuntimeEnabled: isRuntimeEnabled,
                embeddedBundleURLProvider: embeddedBundleURLProvider,
                diagnostics: diagnostics
            )
        #else
            let retention = AdblockGenerationRetention(
                archive: archive,
                contentRuleListStore: compiler
            )
            let recovery = AdblockGenerationRecovery(
                archive: archive,
                publisher: publisher,
                contentRuleListStore: compiler
            )
            let installer = AdblockPreparedBundleInstaller(
                archive: archive,
                publisher: publisher,
                retention: retention,
                mutationGate: mutationGate
            )
            let activation = AdblockPersistedGenerationActivation(
                archive: archive,
                contentBlockingService: service,
                publisher: publisher,
                mutationGate: mutationGate
            )
            let startup = AdblockGenerationStartup(
                archive: archive,
                ruleListProvider: provider,
                recovery: recovery,
                retention: retention,
                preparedBundleInstaller: installer,
                mutationGate: mutationGate,
                isRuntimeEnabled: isRuntimeEnabled,
                embeddedBundleURLProvider: embeddedBundleURLProvider
            )
        #endif
        preparedBundleInstaller = installer
        persistedGenerationActivation = activation
        self.startup = startup
        startupTask = Task { @MainActor [weak self] in
            await self?.runStartup()
        }
    }

    deinit {
        startupTask?.cancel()
    }

    #if DEBUG
        func drainStartupTasksForTests(cancel: Bool = false) async {
            if cancel {
                startupTask?.cancel()
            }
            if let startupTask {
                await startupTask.value
                self.startupTask = nil
            }
            await contentBlockingService.drainScheduledTasksForTests(cancel: cancel)
        }
    #endif

    func contentRuleListDefinitions(
        for protectionGroups: Set<SumiProtectionGroupKind>
    ) throws -> [SumiContentRuleListDefinition] {
        try ruleListProvider.persistedDefinitions(for: protectionGroups)
    }

    func restorePreparedManifestIfAvailable(
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
              SumiProtectionPreparedBundleIdentity.preparedBundleProfileId(
                in: manifest
              ) == profileId
        else {
            #if DEBUG
                startupDiagnostics.recordFallback(
                    reason: "No persisted prepared manifest matched profile \(profileId)"
                )
            #endif
            return nil
        }
        #if DEBUG
            startupDiagnostics.recordManifest(manifest)
            startupDiagnostics.recordGenerationStaleCheck(
                consideredStale: false,
                reason: "Persisted prepared manifest matches requested profile \(profileId)"
            )
        #endif
        try await persistedGenerationActivation.activate(manifest, lease: lease)
        return manifest
    }

    func installPreparedBundle(
        at bundleURL: URL,
        source: SumiAdblockBundleInstallSource,
        profileId: String,
        remoteMetadata: SumiAdblockPreparedBundleRemoteMetadata? = nil
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard await isRuntimeEnabled() else { return nil }
        guard let lease = await mutationGate.acquire() else {
            throw CancellationError()
        }
        defer { mutationGate.release(lease) }
        guard mutationGate.owns(lease), !Task.isCancelled else {
            throw CancellationError()
        }
        return try await preparedBundleInstaller.install(
            at: bundleURL,
            source: source,
            profileId: profileId,
            previousManifest: try await generationArchive.activeManifest(),
            remoteMetadata: remoteMetadata,
            lease: lease
        )
    }

    func stop() {
        startupTask?.cancel()
        mutationGate.stop()
        contentBlockingService.setPolicy(.disabled)
        contentBlockingService.stopRuntime()
    }

    private func runStartup() async {
        guard let lease = await mutationGate.acquire() else { return }
        defer { mutationGate.release(lease) }
        await startup.run(lease: lease)
    }
}

@MainActor
final class AdblockRetainingCompiledRuleListCatalog:
    SumiCompiledContentRuleListCataloging
{
    func cachedIdentifiersToForget(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        let activeIdentifiers = Set(activeRules.map(\.identifier.stringValue))
        return previousRules
            .map(\.identifier.stringValue)
            .filter { !activeIdentifiers.contains($0) }
    }

    func orphanedIdentifiers(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] { [] }

    func forgetIdentifiers(_ identifiers: [String]) {}
}
