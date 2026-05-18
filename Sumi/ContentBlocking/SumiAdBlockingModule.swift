import Combine
import Foundation

enum SumiAdBlockingModuleStatus: Equatable, Sendable {
    case disabled
    case enabledNativeContentBlocking
}

enum SumiAdblockSiteOverride: String, Codable, CaseIterable, Sendable {
    case inherit
    case allowed
    case disabled

    var displayTitle: String {
        switch self {
        case .inherit: return "Use Global Setting"
        case .allowed: return "Enabled"
        case .disabled: return "Disabled"
        }
    }
}

struct SumiAdblockEffectivePolicy: Equatable, Sendable {
    let host: String?
    let isEnabled: Bool
}

struct SumiAdblockSurfaceEligibility: Equatable, Sendable {
    let isEligible: Bool
    let normalizedSiteHost: String?
    let ineligibleReason: String?

    static func evaluate(
        url: URL?,
        normalizer: SumiTrackingProtectionSiteNormalizer
    ) -> SumiAdblockSurfaceEligibility {
        guard let url else {
            return SumiAdblockSurfaceEligibility(isEligible: false, normalizedSiteHost: nil, ineligibleReason: "No URL")
        }
        let scheme = url.scheme?.lowercased()
        if SumiSurface.isEmptyNewTabURL(url) || scheme == "about" {
            return SumiAdblockSurfaceEligibility(isEligible: false, normalizedSiteHost: nil, ineligibleReason: "Sumi empty/new tab surface")
        }
        if scheme == "sumi" {
            return SumiAdblockSurfaceEligibility(isEligible: false, normalizedSiteHost: nil, ineligibleReason: "Internal Sumi surface")
        }
        if scheme == "file" {
            return SumiAdblockSurfaceEligibility(isEligible: false, normalizedSiteHost: nil, ineligibleReason: "Local file URL")
        }
        guard scheme == "http" || scheme == "https" else {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "Unsupported URL scheme: \(scheme ?? "nil")"
            )
        }
        guard let host = normalizer.normalizedHost(for: url) else {
            return SumiAdblockSurfaceEligibility(isEligible: false, normalizedSiteHost: nil, ineligibleReason: "No normalized web host")
        }
        return SumiAdblockSurfaceEligibility(isEligible: true, normalizedSiteHost: host, ineligibleReason: nil)
    }
}

struct SumiAdblockAttachmentState: Equatable, Sendable {
    let siteHost: String?
    let isEnabled: Bool
    let attachedShardIdentifiers: [String]

    init(
        siteHost: String?,
        isEnabled: Bool,
        attachedShardIdentifiers: [String] = []
    ) {
        self.siteHost = siteHost
        self.isEnabled = isEnabled
        self.attachedShardIdentifiers = attachedShardIdentifiers.sorted()
    }

    static func disabled(siteHost: String?) -> SumiAdblockAttachmentState {
        SumiAdblockAttachmentState(siteHost: siteHost, isEnabled: false)
    }
}

struct SumiAdblockAttachmentDiagnostics: Equatable, Sendable {
    let siteHost: String?
    let globalAdblockEnabled: Bool
    let sitePolicyAllowsAdblock: Bool
    let siteOverride: SumiAdblockSiteOverride
    let isEnabled: Bool
    let hasActiveGeneration: Bool
    let attachedShardIdentifiers: [String]
    let expectedNetworkShardIdentifiers: [String]
    let missingShardIdentifiers: [String]
    let activeGenerationId: String?
    let previousGenerationId: String?
    let generationSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let networkShardCount: Int
    let totalNetworkRuleCount: Int
    let lastInstallSummary: String?
    let lastInstallError: String?
    let ineligibleSurfaceReason: String?

    var developerReport: String {
        [
            "Sumi Adblock prepared-bundle diagnostics",
            "globalEnabled=\(globalAdblockEnabled)",
            "siteHost=\(siteHost ?? "nil")",
            "siteOverride=\(siteOverride.rawValue)",
            "effectiveEnabled=\(isEnabled)",
            "activeGeneration=\(hasActiveGeneration)",
            "activeGenerationId=\(activeGenerationId ?? "nil")",
            "previousGenerationId=\(previousGenerationId ?? "nil")",
            "generationSource=\(generationSource?.rawValue ?? "nil")",
            "nativeRuleBundleId=\(nativeRuleBundleId ?? "nil")",
            "bundleProfileId=\(bundleProfileId ?? "nil")",
            "networkShardCount=\(networkShardCount)",
            "totalNetworkRuleCount=\(totalNetworkRuleCount)",
            "expectedNetworkShardIdentifiers=\(expectedNetworkShardIdentifiers.joined(separator: ","))",
            "attachedShardIdentifiers=\(attachedShardIdentifiers.joined(separator: ","))",
            "missingShardIdentifiers=\(missingShardIdentifiers.joined(separator: ","))",
            "lastInstallSummary=\(lastInstallSummary ?? "nil")",
            "lastInstallError=\(lastInstallError ?? "nil")",
            "ineligibleSurfaceReason=\(ineligibleSurfaceReason ?? "nil")",
        ].joined(separator: "\n")
    }
}

struct SumiAdblockCurrentTabDiagnostics: Equatable, Sendable {
    let urlString: String?
    let host: String?
    let normalizedSiteKey: String?
    let globalAdblockEnabled: Bool
    let perSiteAdblockEnabled: Bool
    let reloadRequired: Bool
    let activeGenerationId: String?
    let expectedNetworkShardIdentifiers: [String]
    let recordedAppliedShardIdentifiers: [String]
    let actualAttachedShardIdentifiers: [String]
    let missingShardIdentifiers: [String]
    let unexpectedOldShardIdentifiers: [String]
    let ineligibleSurfaceReason: String?

    var developerReport: String {
        [
            "Sumi Adblock current-tab diagnostics",
            "url=\(urlString ?? "nil")",
            "host=\(host ?? "nil")",
            "normalizedSiteKey=\(normalizedSiteKey ?? "nil")",
            "globalEnabled=\(globalAdblockEnabled)",
            "perSiteEnabled=\(perSiteAdblockEnabled)",
            "reloadRequired=\(reloadRequired)",
            "activeGenerationId=\(activeGenerationId ?? "nil")",
            "expectedNetworkShardIdentifiers=\(expectedNetworkShardIdentifiers.joined(separator: ","))",
            "recordedAppliedShardIdentifiers=\(recordedAppliedShardIdentifiers.joined(separator: ","))",
            "actualAttachedShardIdentifiers=\(actualAttachedShardIdentifiers.joined(separator: ","))",
            "missingShardIdentifiers=\(missingShardIdentifiers.joined(separator: ","))",
            "unexpectedOldShardIdentifiers=\(unexpectedOldShardIdentifiers.joined(separator: ","))",
            "ineligibleSurfaceReason=\(ineligibleSurfaceReason ?? "nil")",
        ].joined(separator: "\n")
    }
}

extension SumiAdblockEffectivePolicy {
    var attachmentState: SumiAdblockAttachmentState {
        SumiAdblockAttachmentState(siteHost: host, isEnabled: isEnabled)
    }
}

@MainActor
final class AdblockSettingsStore: ObservableObject {
    static let shared = AdblockSettingsStore()
    init(userDefaults: UserDefaults = .standard) { _ = userDefaults }
}

@MainActor
final class AdblockSitePolicyStore: ObservableObject {
    static let shared = AdblockSitePolicyStore()

    private enum DefaultsKey {
        static let siteOverrides = "settings.adblock.siteOverrides"
    }

    @Published private(set) var siteOverrides: [String: SumiAdblockSiteOverride]
    private let userDefaults: UserDefaults
    private let siteNormalizer: SumiTrackingProtectionSiteNormalizer
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changesPublisher: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }

    init(
        userDefaults: UserDefaults = .standard,
        registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver()
    ) {
        self.userDefaults = userDefaults
        self.siteNormalizer = SumiTrackingProtectionSiteNormalizer(registrableDomainResolver: registrableDomainResolver)
        siteOverrides = Self.loadSiteOverrides(from: userDefaults)
    }

    func effectivePolicy(for url: URL?, globalEnabled: Bool) -> SumiAdblockEffectivePolicy {
        let host = normalizedHost(for: url)
        guard let host else { return SumiAdblockEffectivePolicy(host: nil, isEnabled: false) }
        switch siteOverrides[host] ?? .inherit {
        case .allowed:
            return SumiAdblockEffectivePolicy(host: host, isEnabled: true)
        case .disabled:
            return SumiAdblockEffectivePolicy(host: host, isEnabled: false)
        case .inherit:
            return SumiAdblockEffectivePolicy(host: host, isEnabled: globalEnabled)
        }
    }

    func override(for url: URL?) -> SumiAdblockSiteOverride {
        guard let host = normalizedHost(for: url) else { return .inherit }
        return siteOverrides[host] ?? .inherit
    }

    func setSiteOverride(_ override: SumiAdblockSiteOverride, for url: URL?) {
        guard let host = normalizedHost(for: url) else { return }
        setSiteOverride(override, forNormalizedHost: host)
    }

    func normalizedHost(for url: URL?) -> String? {
        surfaceEligibility(for: url).normalizedSiteHost
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        SumiAdblockSurfaceEligibility.evaluate(url: url, normalizer: siteNormalizer)
    }

    private func setSiteOverride(_ override: SumiAdblockSiteOverride, forNormalizedHost host: String) {
        var updated = siteOverrides
        if override == .inherit {
            updated.removeValue(forKey: host)
        } else {
            updated[host] = override
        }
        guard updated != siteOverrides else { return }
        siteOverrides = updated
        if let data = try? JSONEncoder().encode(updated.mapValues(\.rawValue)) {
            userDefaults.set(data, forKey: DefaultsKey.siteOverrides)
        }
        changesSubject.send(())
    }

    private static func loadSiteOverrides(from userDefaults: UserDefaults) -> [String: SumiAdblockSiteOverride] {
        guard let data = userDefaults.data(forKey: DefaultsKey.siteOverrides),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded.reduce(into: [:]) { result, entry in
            guard let override = SumiAdblockSiteOverride(rawValue: entry.value), override != .inherit else { return }
            result[entry.key] = override
        }
    }
}

@MainActor
final class AdblockWebKitRuleListStore {
    let contentBlockingService: SumiContentBlockingService
    private let manifestStore: AdblockUpdateManifestStore
    private let ruleListProvider: AdblockManifestRuleListProvider
    private let updateCoordinator: AdblockUpdateCoordinator
    private let isAdblockEnabled: @Sendable () async -> Bool
    private let embeddedBundleURLProvider: @MainActor () -> URL?
    private(set) var lastFailedShardIdentifier: String?
    private(set) var lastUpdateDiagnostics: AdblockUpdateDiagnostics?

    var hasActiveGeneration: Bool { ruleListProvider.activeManifest != nil }
    var activeManifest: AdblockCompiledGenerationManifest? { ruleListProvider.activeManifest }

    init(
        settingsStore: AdblockSettingsStore,
        isAdblockEnabled: @escaping @Sendable () async -> Bool = { true },
        manifestStore: AdblockUpdateManifestStore = AdblockUpdateManifestStore(),
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler(),
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging = AdblockRetainingCompiledRuleListCatalog(),
        embeddedBundleURLProvider: @escaping @MainActor () -> URL? = {
            SumiAdblockNativeRuleBundle.bundledDirectoryURL(for: SumiProtectionBundleProfile.adblock)
        }
    ) {
        _ = settingsStore
        self.manifestStore = manifestStore
        self.isAdblockEnabled = isAdblockEnabled
        self.embeddedBundleURLProvider = embeddedBundleURLProvider
        let provider = AdblockManifestRuleListProvider(
            manifest: nil,
            compiledDefinitionLoader: AdblockManifestRuleListProvider.diskBackedDefinitionLoader(storageRoot: manifestStore.storageRoot)
        )
        ruleListProvider = provider
        contentBlockingService = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            ruleListProvider: provider,
            compiledRuleListCatalog: compiledRuleListCatalog
        )
        let publisher = AdblockRuleListPublisher(ruleListProvider: provider, contentBlockingService: contentBlockingService)
        updateCoordinator = AdblockUpdateCoordinator.production(
            manifestStore: manifestStore,
            publisher: publisher,
            contentRuleListStore: compiler,
            garbageCollector: AdblockGenerationGarbageCollector(manifestStore: manifestStore, contentRuleListStore: compiler)
        )
        Task { [weak self] in
            guard let self else { return }
            await self.loadActiveManifestIfEnabled()
            _ = await self.updateCoordinator.rollbackIfActiveGenerationFailsSmokeCheck()
        }
    }

    func contentRuleListDefinitions(for allowedKinds: Set<AdblockCompiledRuleGroupKind>) throws -> [SumiContentRuleListDefinition] {
        guard let manifest = activeManifest else { return [] }
        let loader = AdblockManifestRuleListProvider.diskBackedDefinitionLoader(storageRoot: manifestStore.storageRoot)
        return try manifest.allNativeShards
            .filter { allowedKinds.contains($0.kind) }
            .sorted { lhs, rhs in
                lhs.kind == rhs.kind ? lhs.id < rhs.id : lhs.kind.rawValue < rhs.kind.rawValue
            }
            .map(loader)
    }

    func contentRuleListDefinitions(for protectionGroups: Set<SumiProtectionGroupKind>) throws -> [SumiContentRuleListDefinition] {
        guard let manifest = activeManifest else { return [] }
        let loader = AdblockManifestRuleListProvider.diskBackedDefinitionLoader(storageRoot: manifestStore.storageRoot)
        return try manifest.allNativeShards
            .filter { shard in
                guard shard.kind == .network else { return false }
                return shard.protectionGroup.map { protectionGroups.contains($0) } ?? false
            }
            .sorted { lhs, rhs in
                if lhs.protectionGroup == rhs.protectionGroup {
                    return lhs.id < rhs.id
                }
                return (lhs.protectionGroup?.rawValue ?? "") < (rhs.protectionGroup?.rawValue ?? "")
            }
            .map(loader)
    }

    func loadActiveManifestIfEnabled() async {
        guard await isAdblockEnabled() else { return }
        let observedManifest = ruleListProvider.activeManifest
        do {
            let manifest = try await manifestStore.activeManifest()
            do {
                if try await installEmbeddedBundleIfNeeded(previousManifest: manifest) != nil { return }
            } catch where manifest != nil {
                try await manifestStore.validateCompiledShardFiles(for: manifest!)
                updateManifestIfNoNewerPublication(manifest, replacing: observedManifest)
                lastFailedShardIdentifier = nil
                return
            }
            if let manifest { try await manifestStore.validateCompiledShardFiles(for: manifest) }
            updateManifestIfNoNewerPublication(manifest, replacing: observedManifest)
            lastFailedShardIdentifier = nil
        } catch let diagnostics as AdblockUpdateDiagnostics {
            lastFailedShardIdentifier = diagnostics.failedShardIdentifier
            lastUpdateDiagnostics = diagnostics
            updateManifestIfNoNewerPublication(nil, replacing: observedManifest)
        } catch {
            lastFailedShardIdentifier = "manifest-load"
            lastUpdateDiagnostics = AdblockUpdateDiagnostics(summary: error.localizedDescription)
            updateManifestIfNoNewerPublication(nil, replacing: observedManifest)
        }
    }

    private func updateManifestIfNoNewerPublication(
        _ manifest: AdblockCompiledGenerationManifest?,
        replacing observedManifest: AdblockCompiledGenerationManifest?
    ) {
        guard ruleListProvider.activeManifest == observedManifest else { return }
        ruleListProvider.updateManifest(manifest)
    }

    func restorePreparedManifestIfAvailable(profileId: String) async throws -> AdblockCompiledGenerationManifest? {
        guard await isAdblockEnabled() else { return nil }
        guard let manifest = try await manifestStore.activeManifest(),
              Self.isPreparedManifest(manifest, profileId: profileId)
        else { return nil }
        try await publishPersistedManifest(manifest)
        lastFailedShardIdentifier = nil
        lastUpdateDiagnostics = AdblockUpdateDiagnostics(
            summary: "success: restored prepared Adblock bundle",
            generationSource: manifest.generationSource,
            bundleProfileId: profileId,
            nativeRuleBundleId: manifest.nativeRuleBundleId
        )
        return manifest
    }

    func requestPreparedBundleInstall(
        bundleURL: URL,
        source: SumiAdblockBundleInstallSource,
        profileId: String,
        remoteMetadata: SumiAdblockPreparedBundleRemoteMetadata? = nil
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard await isAdblockEnabled() else { return nil }
        return try await installPreparedBundle(
            at: bundleURL,
            source: source,
            requestedProfileId: profileId,
            previousManifest: try await manifestStore.activeManifest(),
            skipIfAlreadyInstalled: false,
            remoteMetadata: remoteMetadata
        )
    }

#if DEBUG
    func requestEmbeddedBundleInstall(
        bundleURL: URL,
        source: SumiAdblockBundleInstallSource = .appResource,
        profileId: String? = nil
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard await isAdblockEnabled() else { return nil }
        return try await installPreparedBundle(
            at: bundleURL,
            source: source,
            requestedProfileId: profileId,
            previousManifest: try await manifestStore.activeManifest(),
            skipIfAlreadyInstalled: false,
            remoteMetadata: nil
        )
    }
#endif

    private func installEmbeddedBundleIfNeeded(
        previousManifest: AdblockCompiledGenerationManifest?
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard let bundleURL = embeddedBundleURLProvider() else { return nil }
        return try await installPreparedBundle(
            at: bundleURL,
            source: .appResource,
            requestedProfileId: SumiProtectionBundleProfile.adblock,
            previousManifest: previousManifest,
            skipIfAlreadyInstalled: true,
            remoteMetadata: nil
        )
    }

    private func installPreparedBundle(
        at bundleURL: URL,
        source: SumiAdblockBundleInstallSource,
        requestedProfileId: String?,
        previousManifest: AdblockCompiledGenerationManifest?,
        skipIfAlreadyInstalled: Bool,
        remoteMetadata: SumiAdblockPreparedBundleRemoteMetadata?
    ) async throws -> AdblockCompiledGenerationManifest? {
        let bundle: SumiAdblockNativeRuleBundle
        do {
            bundle = try SumiAdblockNativeRuleBundle.load(directoryURL: bundleURL)
        } catch {
            throw diagnostics(
                summary: "Adblock bundle install failed before publish: \(error.localizedDescription)",
                stage: Self.bundleLoadFailureStage(error),
                source: source,
                profileId: requestedProfileId,
                bundleURL: bundleURL,
                error: error
            )
        }
        if skipIfAlreadyInstalled,
           previousManifest?.generationSource == source.generationSource,
           previousManifest?.nativeRuleBundleId == bundle.manifest.bundleId {
            return nil
        }
        let manifest = bundle.compiledGenerationManifest(
            previousManifest: previousManifest,
            installedDate: Date(),
            generationSource: source.generationSource,
            remoteMetadata: remoteMetadata
        )
        let definitions = try bundle.contentRuleListDefinitions()
        let publication = try await updateCoordinator.prepareEmbeddedBundlePublication(
            manifest: manifest,
            definitions: definitions
        )
        let stagedShardURLs = try bundle.stagedShardURLs()
        do {
            try await manifestStore.commit(manifest: manifest, stagedCompiledShardURLs: stagedShardURLs)
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
        await updateCoordinator.commitEmbeddedBundlePublication(publication)
        lastFailedShardIdentifier = nil
        lastUpdateDiagnostics = AdblockUpdateDiagnostics(
            summary: "success: Adblock bundle installed",
            generationSource: source.generationSource,
            bundleProfileId: bundle.manifest.profileId,
            bundlePath: bundleURL.path,
            nativeRuleBundleId: bundle.manifest.bundleId
        )
        return manifest
    }

    private func publishPersistedManifest(_ manifest: AdblockCompiledGenerationManifest) async throws {
        try await manifestStore.validateCompiledShardFiles(for: manifest)
        let definitions = try await manifestStore.compiledShardDefinitions(for: manifest)
        let preparedUpdate = try await contentBlockingService.prepareRuleListUpdate(
            ruleLists: definitions,
            retainEncodedRuleListsInPreparedPolicy: false
        )
        ruleListProvider.updateManifest(manifest)
        contentBlockingService.commitPreparedContentBlockingUpdate(preparedUpdate)
    }

    private static func isPreparedManifest(_ manifest: AdblockCompiledGenerationManifest, profileId: String) -> Bool {
        manifest.bundleProfileId == profileId || manifest.nativeRuleBundleId?.contains(profileId) == true
    }

    private func diagnostics(
        summary: String,
        stage: AdblockUpdateFailureStage,
        source: SumiAdblockBundleInstallSource,
        profileId: String?,
        bundleURL: URL,
        error: Error
    ) -> AdblockUpdateDiagnostics {
        let diagnostics = AdblockUpdateDiagnostics(
            summary: "\(summary); bundleSource=\(source.rawValue); bundleProfileId=\(profileId ?? "nil"); bundlePath=\(bundleURL.path); details=\(error.localizedDescription)",
            stage: stage,
            generationSource: source.generationSource,
            bundleProfileId: profileId,
            bundlePath: bundleURL.path
        )
        lastFailedShardIdentifier = diagnostics.failedShardIdentifier
        lastUpdateDiagnostics = diagnostics
        return diagnostics
    }

    private static func bundleLoadFailureStage(_ error: Error) -> AdblockUpdateFailureStage {
        guard let error = error as? SumiAdblockNativeRuleBundleError else { return .embeddedBundleManifestRead }
        switch error {
        case .missingManifest, .unsupportedSchemaVersion, .unsupportedNativeCSSSafetyPolicyVersion:
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

@MainActor
final class AdblockRetainingCompiledRuleListCatalog: SumiCompiledContentRuleListCataloging {
    func cachedIdentifiersToForget(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        let activeIdentifiers = Set(activeRules.map(\.identifier.stringValue))
        return previousRules.map(\.identifier.stringValue).filter { !activeIdentifiers.contains($0) }
    }

    func staleIdentifiers(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] { [] }

    func forgetIdentifiers(_ identifiers: [String]) {}
}

@MainActor
final class SumiAdBlockingModule {
    static let shared = SumiAdBlockingModule()

    private let moduleRegistry: SumiModuleRegistry
    private let settingsFactory: @MainActor () -> AdblockSettingsStore
    private let sitePolicyFactory: @MainActor () -> AdblockSitePolicyStore
    private let ruleListStoreFactory: @MainActor (AdblockSettingsStore, @escaping @Sendable () async -> Bool) -> AdblockWebKitRuleListStore
    private let preparedBundleResourceURL: URL?
    private let preparedBundleRemoteRootURL: URL?
    private let preparedBundleGeneratedRootURL: URL?
    private var cachedSettingsStore: AdblockSettingsStore?
    private var cachedSitePolicyStore: AdblockSitePolicyStore?
    private var cachedRuleListStore: AdblockWebKitRuleListStore?
    private var preparedBundleRuntimeEnabled = false

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        settingsFactory: (@MainActor () -> AdblockSettingsStore)? = nil,
        sitePolicyFactory: (@MainActor () -> AdblockSitePolicyStore)? = nil,
        preparedBundleResourceURL: URL? = Bundle.main.resourceURL,
        preparedBundleRemoteRootURL: URL? = SumiRemoteAdblockBundleCache.defaultRootDirectory(),
        preparedBundleGeneratedRootURL: URL? = nil,
        ruleListStoreFactory: @escaping @MainActor (AdblockSettingsStore, @escaping @Sendable () async -> Bool) -> AdblockWebKitRuleListStore = {
            AdblockWebKitRuleListStore(settingsStore: $0, isAdblockEnabled: $1)
        }
    ) {
        self.moduleRegistry = moduleRegistry
        self.settingsFactory = settingsFactory ?? { AdblockSettingsStore(userDefaults: moduleRegistry.userDefaults) }
        self.sitePolicyFactory = sitePolicyFactory ?? { AdblockSitePolicyStore(userDefaults: moduleRegistry.userDefaults) }
        self.ruleListStoreFactory = ruleListStoreFactory
        self.preparedBundleResourceURL = preparedBundleResourceURL
        self.preparedBundleRemoteRootURL = preparedBundleRemoteRootURL
        self.preparedBundleGeneratedRootURL = preparedBundleGeneratedRootURL
    }

    var isEnabled: Bool { moduleRegistry.isEnabled(.adBlocking) }
    var isPreparedBundleRuntimeEnabled: Bool { preparedBundleRuntimeEnabled || isEnabled }
    var status: SumiAdBlockingModuleStatus { isEnabled ? .enabledNativeContentBlocking : .disabled }
    var hasLoadedRuntime: Bool { cachedRuleListStore != nil }

    func setEnabled(_ isEnabled: Bool) {
        moduleRegistry.setEnabled(isEnabled, for: .adBlocking)
        if !isEnabled && !isPreparedBundleRuntimeEnabled {
            cachedRuleListStore?.contentBlockingService.setPolicy(.disabled)
            cachedRuleListStore = nil
        }
    }

    func setPreparedBundleRuntimeEnabled(_ isEnabled: Bool) {
        preparedBundleRuntimeEnabled = isEnabled
        if !isEnabled && !self.isEnabled {
            cachedRuleListStore?.contentBlockingService.setPolicy(.disabled)
            cachedRuleListStore = nil
        }
    }

    func activeManifestIfLoaded() -> AdblockCompiledGenerationManifest? {
        cachedRuleListStore?.activeManifest
    }

    func contentRuleListDefinitions(
        for allowedKinds: Set<AdblockCompiledRuleGroupKind>
    ) throws -> [SumiContentRuleListDefinition] {
        try ruleListStoreIfPreparedBundleRuntimeEnabled().contentRuleListDefinitions(for: allowedKinds)
    }

    func contentRuleListDefinitions(
        for protectionGroups: Set<SumiProtectionGroupKind>
    ) throws -> [SumiContentRuleListDefinition] {
        try ruleListStoreIfPreparedBundleRuntimeEnabled().contentRuleListDefinitions(for: protectionGroups)
    }

    func installPreparedNativeRuleBundle(profileId: String) async throws -> AdblockCompiledGenerationManifest? {
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
        return try await ruleListStoreIfPreparedBundleRuntimeEnabled().requestPreparedBundleInstall(
            bundleURL: resolvedBundle.bundleURL,
            source: resolvedBundle.source,
            profileId: profileId,
            remoteMetadata: resolvedBundle.remoteMetadata
        )
    }

    func restorePreparedNativeRuleBundleForStartup(profileId: String) async throws -> AdblockCompiledGenerationManifest? {
        guard isPreparedBundleRuntimeEnabled else {
            throw AdblockUpdateDiagnostics(
                summary: "Enable Sumi protection before restoring prepared bundle \(profileId).",
                generationSource: nil,
                bundleProfileId: profileId
            )
        }
        let store = ruleListStoreIfPreparedBundleRuntimeEnabled()
        if let restored = try await store.restorePreparedManifestIfAvailable(profileId: profileId) {
            return restored
        }
        return try await installPreparedNativeRuleBundle(profileId: profileId)
    }

    func preparedNativeRuleBundleDiscovery(profileId: String) -> SumiPreparedAdblockBundleDiscovery {
        SumiPreparedAdblockBundleResolver.discover(
            profileId: profileId,
            resourceURL: preparedBundleResourceURL,
            remoteBundlesRootURL: preparedBundleRemoteRootURL,
            generatedBundlesRootURL: preparedBundleGeneratedRootURL
        )
    }

    func normalizedSiteHost(for url: URL?) -> String? {
        sitePolicyStoreIfEnabled().normalizedHost(for: url)
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        sitePolicyStoreIfEnabled().surfaceEligibility(for: url)
    }

    func effectivePolicy(for url: URL?) -> SumiAdblockEffectivePolicy {
        let store = sitePolicyStoreIfEnabled()
        guard isEnabled else {
            return SumiAdblockEffectivePolicy(host: store.normalizedHost(for: url), isEnabled: false)
        }
        return store.effectivePolicy(for: url, globalEnabled: true)
    }

    func desiredAttachmentState(for url: URL?) -> SumiAdblockAttachmentState {
        let policy = effectivePolicy(for: url)
        guard isEnabled, policy.isEnabled, surfaceEligibility(for: url).isEligible else {
            return policy.attachmentState
        }
        let identifiers = cachedRuleListStore?.activeManifest?.networkShards.map(\.webKitIdentifier) ?? []
        return SumiAdblockAttachmentState(
            siteHost: policy.host,
            isEnabled: !identifiers.isEmpty,
            attachedShardIdentifiers: identifiers
        )
    }

    func currentTabDiagnostics(
        for url: URL?,
        appliedState: SumiAdblockAttachmentState?,
        reloadRequired: Bool,
        actualAttachedRuleListIdentifiers: [String]? = nil
    ) -> SumiAdblockCurrentTabDiagnostics {
        let eligibility = surfaceEligibility(for: url)
        let policy = effectivePolicy(for: url)
        let manifest = activeManifestIfLoaded()
        let expected = eligibility.isEligible && policy.isEnabled
            ? manifest?.networkShards.map(\.webKitIdentifier).sorted() ?? []
            : []
        let recorded = appliedState?.attachedShardIdentifiers ?? []
        let actual = (actualAttachedRuleListIdentifiers ?? recorded)
            .filter { $0.hasPrefix("sumi.adblock.") }
            .sorted()
        let expectedSet = Set(expected)
        let actualSet = Set(actual)
        return SumiAdblockCurrentTabDiagnostics(
            urlString: url?.absoluteString,
            host: url?.host,
            normalizedSiteKey: policy.host,
            globalAdblockEnabled: isEnabled,
            perSiteAdblockEnabled: policy.isEnabled,
            reloadRequired: reloadRequired,
            activeGenerationId: manifest?.activeGenerationId,
            expectedNetworkShardIdentifiers: expected,
            recordedAppliedShardIdentifiers: recorded,
            actualAttachedShardIdentifiers: actual,
            missingShardIdentifiers: expected.filter { !actualSet.contains($0) },
            unexpectedOldShardIdentifiers: actual.filter { !expectedSet.contains($0) },
            ineligibleSurfaceReason: eligibility.ineligibleReason
        )
    }

#if DEBUG
    func embeddedAdblockBundleSnapshot() -> SumiEmbeddedAdblockBundleSnapshot {
        SumiEmbeddedAdblockBundleCatalog.snapshot(
            generatedBundlesRootURL: preparedBundleGeneratedRootURL
        )
    }

    func installEmbeddedAdblockBundle(
        profileId: String,
        source: SumiAdblockBundleInstallSource = .appResource
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard isEnabled else {
            throw AdblockUpdateDiagnostics(
                summary: "Enable built-in Adblock before installing an Adblock bundle.",
                generationSource: source.generationSource,
                bundleProfileId: profileId
            )
        }
        let bundleURL: URL?
        switch source {
        case .appResource:
            bundleURL = SumiEmbeddedAdblockBundleCatalog.embeddedBundleURL(for: profileId)
        case .developmentBundle:
            bundleURL = SumiEmbeddedAdblockBundleCatalog.developmentBundleURL(
                for: profileId,
                generatedBundlesRootURL: preparedBundleGeneratedRootURL
            )
        case .remoteReleaseBundle:
            bundleURL = nil
        }
        guard let bundleURL else {
            throw AdblockUpdateDiagnostics(
                summary: "No \(source.displayTitle) Adblock bundle found for profile \(profileId).",
                generationSource: source.generationSource,
                bundleProfileId: profileId
            )
        }
        return try await ruleListStoreIfEnabled().requestEmbeddedBundleInstall(
            bundleURL: bundleURL,
            source: source,
            profileId: profileId
        )
    }
#endif

    func siteOverride(for url: URL?) -> SumiAdblockSiteOverride {
        sitePolicyStoreIfEnabled().override(for: url)
    }

    func setSiteOverride(_ override: SumiAdblockSiteOverride, for url: URL?) {
        sitePolicyStoreIfEnabled().setSiteOverride(override, for: url)
    }

    func sitePolicyChangesPublisher() -> AnyPublisher<Void, Never> {
        sitePolicyStoreIfEnabled().changesPublisher
    }

    func settingsIfEnabled() -> AdblockSettingsStore? {
        guard isEnabled else { return nil }
        if let cachedSettingsStore { return cachedSettingsStore }
        let settings = settingsFactory()
        cachedSettingsStore = settings
        return settings
    }

    func sitePolicyStoreIfEnabled() -> AdblockSitePolicyStore {
        if let cachedSitePolicyStore { return cachedSitePolicyStore }
        let store = sitePolicyFactory()
        cachedSitePolicyStore = store
        return store
    }

    private func ruleListStoreIfEnabled() -> AdblockWebKitRuleListStore {
        ruleListStore()
    }

    private func ruleListStoreIfPreparedBundleRuntimeEnabled() -> AdblockWebKitRuleListStore {
        ruleListStore()
    }

    private func ruleListStore() -> AdblockWebKitRuleListStore {
        if let cachedRuleListStore { return cachedRuleListStore }
        let settings = settingsIfEnabled() ?? settingsFactory()
        let store = ruleListStoreFactory(settings, { [weak self] in
            await MainActor.run { self?.isPreparedBundleRuntimeEnabled == true }
        })
        cachedRuleListStore = store
        return store
    }
}
