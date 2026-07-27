import Combine
import Foundation
import SumiDomain

/// Optional-module lifetime boundary for Adblock. The applied protection level
/// is the single source of truth for lazy site-policy and WebKit runtime state.
@MainActor
final class SumiAdBlockingModule {
    private let sitePolicyFactory: @MainActor () -> AdblockSitePolicyStore
    private let ruleListRuntimeFactory:
        @MainActor (@escaping @Sendable () async -> Bool) -> AdblockRuleListRuntime
    private let preparedBundleResourceURL: URL?
    private let preparedBundleRemoteRootURL: URL?
    private let preparedBundleGeneratedRootURL: URL?
    private let preparedBundleResolver: SumiPreparedAdblockBundleResolver
    private var cachedSitePolicyStore: AdblockSitePolicyStore?
    private var cachedRuleListRuntime: AdblockRuleListRuntime?
    private var runtimeLevel = SumiProtectionLevel.off
    private let disabledSurfaceNormalizer = SumiProtectionSiteNormalizer()
    private let disabledSitePolicyChangesSubject = PassthroughSubject<Void, Never>()

    init(
        moduleRegistry: SumiModuleRegistry,
        database: SumiDatabase? = nil,
        sitePolicyFactory: (@MainActor () -> AdblockSitePolicyStore)? = nil,
        preparedBundleResourceURL: URL? = Bundle.main.resourceURL,
        preparedBundleRemoteRootURL: URL? =
            SumiRemoteAdblockBundleCache.defaultRootDirectory(),
        preparedBundleGeneratedRootURL: URL? = nil,
        preparedBundleResolver: SumiPreparedAdblockBundleResolver =
            SumiPreparedAdblockBundleResolver(),
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        ruleListRuntimeFactory: (@MainActor (
            @escaping @Sendable () async -> Bool
        ) -> AdblockRuleListRuntime)? = nil
    ) {
        self.sitePolicyFactory = sitePolicyFactory
            ?? { AdblockSitePolicyStore(database: database) }
        self.ruleListRuntimeFactory = ruleListRuntimeFactory ?? {
            AdblockRuleListRuntime(
                isRuntimeEnabled: $0,
                compiledRuleListCatalog: compiledRuleListCatalog
            )
        }
        self.preparedBundleResourceURL = preparedBundleResourceURL
        self.preparedBundleRemoteRootURL = preparedBundleRemoteRootURL
        self.preparedBundleGeneratedRootURL = preparedBundleGeneratedRootURL
        self.preparedBundleResolver = preparedBundleResolver
    }

    var isEnabled: Bool { runtimeLevel == .adblock }
    var isPreparedBundleRuntimeEnabled: Bool { runtimeLevel != .off }
    var hasLoadedRuntime: Bool { cachedRuleListRuntime != nil }

    func setRuntimeLevel(_ level: SumiProtectionLevel) {
        runtimeLevel = level
        if level != .adblock {
            cachedSitePolicyStore = nil
        }
        if level == .off {
            cachedRuleListRuntime?.stop()
            cachedRuleListRuntime = nil
        }
    }

    #if DEBUG
        func drainRuleListTasksForTests(cancel: Bool = false) async {
            await cachedRuleListRuntime?.drainStartupTasksForTests(cancel: cancel)
        }
    #endif

    func activeManifestIfLoaded() -> AdblockCompiledGenerationManifest? {
        cachedRuleListRuntime?.activeManifest
    }

    func contentRuleListDefinitions(
        for protectionGroups: Set<SumiProtectionGroupKind>
    ) throws -> [SumiContentRuleListDefinition] {
        guard isPreparedBundleRuntimeEnabled else { return [] }
        return try ruleListRuntime().contentRuleListDefinitions(
            for: protectionGroups
        )
    }

    func installPreparedNativeRuleBundle(
        profileId: String
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard isPreparedBundleRuntimeEnabled else {
            throw AdblockUpdateDiagnostics(
                summary: "Enable Sumi protection before installing prepared bundle \(profileId).",
                generationSource: .embeddedBundle,
                bundleProfileId: profileId
            )
        }
        let discovery = preparedNativeRuleBundleDiscovery(profileId: profileId)
        guard let resolvedBundle = discovery.resolvedBundle else {
            throw AdblockUpdateDiagnostics(
                summary: discovery.failureSummary,
                failedShardIdentifier: "prepared-bundle-\(profileId)",
                generationSource: nil,
                bundleProfileId: profileId
            )
        }
        return try await ruleListRuntime().installPreparedBundle(
            at: resolvedBundle.bundleURL,
            source: resolvedBundle.source,
            profileId: profileId,
            remoteMetadata: resolvedBundle.remoteMetadata
        )
    }

    func restorePreparedNativeRuleBundleForStartup(
        profileId: String
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard isPreparedBundleRuntimeEnabled else {
            throw AdblockUpdateDiagnostics(
                summary: "Enable Sumi protection before restoring prepared bundle \(profileId).",
                generationSource: nil,
                bundleProfileId: profileId
            )
        }
        let runtime = ruleListRuntime()
        if let restored = try await runtime.restorePreparedManifestIfAvailable(
            profileId: profileId
        ) {
            return restored
        }
        return try await installPreparedNativeRuleBundle(profileId: profileId)
    }

    func preparedNativeRuleBundleDiscovery(
        profileId: String
    ) -> SumiPreparedAdblockBundleDiscovery {
        preparedBundleResolver.discover(
            profileId: profileId,
            resourceURL: preparedBundleResourceURL,
            remoteBundlesRootURL: preparedBundleRemoteRootURL,
            generatedBundlesRootURL: preparedBundleGeneratedRootURL
        )
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        if let store = sitePolicyStore() {
            return store.surfaceEligibility(for: url)
        }
        return SumiAdblockSurfaceEligibility.evaluate(
            url: url,
            normalizer: disabledSurfaceNormalizer
        )
    }

    func effectivePolicy(for url: URL?) -> SumiAdblockEffectivePolicy {
        guard let store = sitePolicyStore() else {
            let host = SumiAdblockSurfaceEligibility.evaluate(
                url: url,
                normalizer: disabledSurfaceNormalizer
            ).normalizedSiteHost
            return SumiAdblockEffectivePolicy(host: host, isEnabled: false)
        }
        return store.effectivePolicy(for: url, globalEnabled: true)
    }

    func siteOverride(for url: URL?) -> SumiAdblockSiteOverride {
        sitePolicyStore()?.override(for: url) ?? .inherit
    }

    func setSiteOverride(_ override: SumiAdblockSiteOverride, for url: URL?) {
        sitePolicyStore()?.setSiteOverride(override, for: url)
    }

    func sitePolicyChangesPublisher() -> AnyPublisher<Void, Never> {
        sitePolicyStore()?.changesPublisher
            ?? disabledSitePolicyChangesSubject.eraseToAnyPublisher()
    }

    private func sitePolicyStore() -> AdblockSitePolicyStore? {
        guard isEnabled else { return nil }
        if let cachedSitePolicyStore { return cachedSitePolicyStore }
        let store = sitePolicyFactory()
        cachedSitePolicyStore = store
        return store
    }

    private func ruleListRuntime() -> AdblockRuleListRuntime {
        if let cachedRuleListRuntime { return cachedRuleListRuntime }
        let runtime = ruleListRuntimeFactory { [weak self] in
            await MainActor.run {
                self?.isPreparedBundleRuntimeEnabled == true
            }
        }
        cachedRuleListRuntime = runtime
        return runtime
    }
}
