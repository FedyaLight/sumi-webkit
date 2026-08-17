import Combine
import Foundation
import SumiDomain

/// Optional-module lifetime boundary for Adblock. The applied Adblock level
/// is the single source of truth for lazy site-policy and WebKit runtime state.
@MainActor
final class SumiAdBlockingModule {
    private let sitePolicyFactory: @MainActor () -> AdblockSitePolicyStore
    private let ruleListRuntimeFactory:
        @MainActor (@escaping @Sendable () async -> Bool) -> AdblockRuleListRuntime
    let filterListCatalog: SumiFilterListCatalog?
    private var cachedSitePolicyStore: AdblockSitePolicyStore?
    private var cachedRuleListRuntime: AdblockRuleListRuntime?
    private var cachedAdvancedPageRuntimeSource: String?
    private var runtimeLevel = SumiProtectionLevel.off
    private let disabledSurfaceNormalizer = SumiProtectionSiteNormalizer()
    private let disabledSitePolicyChangesSubject = PassthroughSubject<Void, Never>()
    private weak var urlCleaningHost: (any SumiURLCleaningContributionHosting)?
    private var urlCleaningProfileIDs: Set<UUID> = []

    init(
        database: SumiDatabase? = nil,
        sitePolicyFactory: (@MainActor () -> AdblockSitePolicyStore)? = nil,
        filterListCatalog: SumiFilterListCatalog? = try? .bundled(),
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
        self.filterListCatalog = filterListCatalog
    }

    var isEnabled: Bool { runtimeLevel == .adblock }
    var hasLoadedRuntime: Bool { cachedRuleListRuntime != nil }

    func setRuntimeLevel(_ level: SumiProtectionLevel) {
        runtimeLevel = level
        if level != .adblock {
            cachedSitePolicyStore = nil
        }
        if level == .off {
            cachedRuleListRuntime?.stop()
            cachedRuleListRuntime = nil
            cachedAdvancedPageRuntimeSource = nil
        }
        refreshURLCleaningContributions()
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
        guard isEnabled else { return [] }
        return try ruleListRuntime().contentRuleListDefinitions(
            for: protectionGroups
        )
    }

    /// The only tab-facing interface of the advanced blocker. Callers receive
    /// an inert page-script adapter and do not participate in engine or
    /// generation lifecycle.
    func normalTabUserScripts(for url: URL?) -> [SumiPageScript] {
        guard isEnabled,
              effectivePolicy(for: url).isEnabled,
              let source = advancedPageRuntimeSource()
        else {
            return []
        }
        return [
            SumiAdvancedBlockingPageScript(
                runtimeSource: source,
                lookup: { [weak self] document in
                    guard let self,
                          self.isEnabled,
                          self.effectivePolicy(
                            for: document.topURL ?? document.pageURL
                          ).isEnabled,
                          let runtime = self.cachedRuleListRuntime
                    else {
                        return nil
                    }
                    do {
                        return try await runtime.advancedConfiguration(
                            for: document
                        )
                    } catch { return nil }
                }
            ),
        ]
    }

    private func urlCleaningContributionIfLoaded() -> SumiURLCleaningContribution? {
        guard isEnabled, let runtime = cachedRuleListRuntime else {
            return nil
        }
        return runtime.urlCleaningContribution(
            disabledDomains: sitePolicyStore()?.disabledHosts ?? []
        )
    }

    func reconcileURLCleaning(
        for profileID: UUID,
        using host: any SumiURLCleaningContributionHosting
    ) {
        urlCleaningHost = host
        urlCleaningProfileIDs.insert(profileID)
        host.reconcileInternalURLCleaning(
            urlCleaningContributionIfLoaded(),
            profileID: profileID
        )
    }

    func forgetURLCleaningProfile(_ profileID: UUID) {
        urlCleaningProfileIDs.remove(profileID)
    }

    func installGeneratedRuleBundle(
        at bundleURL: URL
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard isEnabled else {
            throw AdblockUpdateDiagnostics(
                summary: "Enable Adblock before installing a local filter generation.",
                bundleProfileId: SumiProtectionBundleProfile.adblock,
                bundlePath: bundleURL.path
            )
        }
        return try await ruleListRuntime().installGeneratedBundle(
            at: bundleURL,
            profileId: SumiProtectionBundleProfile.adblock
        )
    }

    func restoreLocalGenerationForStartup(
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard isEnabled else {
            throw AdblockUpdateDiagnostics(
                summary: "Enable Adblock before restoring its local generation.",
                bundleProfileId: SumiProtectionBundleProfile.adblock
            )
        }
        return try await ruleListRuntime().restoreLocalManifestIfAvailable(
            profileId: SumiProtectionBundleProfile.adblock
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
        refreshURLCleaningContributions()
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
                self?.isEnabled == true
            }
        }
        cachedRuleListRuntime = runtime
        runtime.setActiveManifestDidChange { [weak self] in
            self?.refreshURLCleaningContributions()
        }
        return runtime
    }

    private func refreshURLCleaningContributions() {
        guard let urlCleaningHost else { return }
        let contribution = urlCleaningContributionIfLoaded()
        for profileID in urlCleaningProfileIDs {
            urlCleaningHost.reconcileInternalURLCleaning(
                contribution,
                profileID: profileID
            )
        }
    }

    private func advancedPageRuntimeSource() -> String? {
        if let cachedAdvancedPageRuntimeSource {
            return cachedAdvancedPageRuntimeSource
        }
        let source: String
        do {
            source = try SumiAdvancedBlockingResourceLoader
                .pageRuntimeSource()
        } catch { return nil }
        guard source.isEmpty == false else { return nil }
        cachedAdvancedPageRuntimeSource = source
        return source
    }
}
