import Combine
import Foundation

enum SumiAdBlockingModuleStatus: Equatable, Sendable {
    case disabled
    case enabledNativeContentBlocking
}

enum SumiAdblockCosmeticMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case nativeCSS
    case enhancedRuntime

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .off:
            return "Off"
        case .nativeCSS:
            return "Native CSS hiding"
        case .enhancedRuntime:
            return "Enhanced cleanup"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Request blocking only."
        case .nativeCSS:
            return "WebKit-native hiding, no runtime script."
        case .enhancedRuntime:
            return "Adds opt-in compatibility cleanup for difficult pages and may use more CPU or memory."
        }
    }
}

enum SumiAdblockSiteOverride: String, Codable, CaseIterable, Sendable {
    case inherit
    case allowed
    case disabled

    var displayTitle: String {
        switch self {
        case .inherit:
            return "Use Global Setting"
        case .allowed:
            return "Enabled"
        case .disabled:
            return "Disabled"
        }
    }
}

struct SumiAdblockEffectivePolicy: Equatable, Sendable {
    let host: String?
    let isEnabled: Bool
}

struct SumiAdblockAttachmentState: Equatable, Sendable {
    let siteHost: String?
    let isEnabled: Bool
    let hasEnhancedRuntime: Bool

    init(siteHost: String?, isEnabled: Bool, hasEnhancedRuntime: Bool = false) {
        self.siteHost = siteHost
        self.isEnabled = isEnabled
        self.hasEnhancedRuntime = hasEnhancedRuntime
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
    let attachedNativeGroups: [AdblockCompiledRuleGroupKind]
    let attachedShardIdentifiers: [String]
    let contentRuleListIdentifiers: [String]
    let selectedListIdentifiers: [String]
    let selectedNativeProfile: AdblockFilterListProfileKind?
    let nativeCompiler: NativeContentBlockingCompilerIdentity?
    let nativeCompilationSummary: NativeContentBlockingCompilationSummary?
    let nativeSourceLists: [NativeContentBlockingSourceList]
    let networkShardCount: Int
    let nativeCSSShardCount: Int
    let totalNetworkRuleCount: Int
    let totalNativeCSSRuleCount: Int
    let largestShardJSONByteCount: Int
    let failedShardIdentifier: String?
    let cosmeticMode: SumiAdblockCosmeticMode?
    let enhancedRuntimeIsEnabled: Bool
    let trackingProtectionModuleEnabled: Bool
    let generationIsStale: Bool
}

extension SumiAdblockAttachmentDiagnostics {
    var developerReport: String {
        [
            "Sumi Adblock diagnostics",
            "globalEnabled=\(globalAdblockEnabled)",
            "siteHost=\(siteHost ?? "nil")",
            "siteOverride=\(siteOverride.rawValue)",
            "sitePolicyAllowsAdblock=\(sitePolicyAllowsAdblock)",
            "effectiveEnabled=\(isEnabled)",
            "selectedNativeProfile=\(selectedNativeProfile?.rawValue ?? "nil")",
            "nativeCompiler=\(nativeCompiler.map { "\($0.name) \($0.version)" } ?? "nil")",
            "activeGeneration=\(hasActiveGeneration)",
            "generationIsStale=\(generationIsStale)",
            "selectedListIDs=\(selectedListIdentifiers.joined(separator: ","))",
            "networkShardCount=\(networkShardCount)",
            "nativeCSSShardCount=\(nativeCSSShardCount)",
            "attachedGroups=\(attachedNativeGroups.map(\.rawValue).joined(separator: ","))",
            "attachedShardIdentifiers=\(attachedShardIdentifiers.joined(separator: ","))",
            "totalNetworkRuleCount=\(totalNetworkRuleCount)",
            "totalNativeCSSRuleCount=\(totalNativeCSSRuleCount)",
            "largestShardJSONByteCount=\(largestShardJSONByteCount)",
            "failedShardIdentifier=\(failedShardIdentifier ?? "nil")",
            "ruleCapHit=\(nativeCompilationSummary?.ruleCap.wasHit.description ?? "nil")",
            "discardedRuleCount=\(nativeCompilationSummary?.ruleCap.discardedRuleCount.description ?? "nil")",
            "trackingProtectionEnabled=\(trackingProtectionModuleEnabled)",
            "cosmeticMode=\(cosmeticMode?.rawValue ?? "nil")",
            "enhancedRuntimeEnabled=\(enhancedRuntimeIsEnabled)",
        ].joined(separator: "\n")
    }
}

extension SumiAdblockEffectivePolicy {
    var attachmentState: SumiAdblockAttachmentState {
        SumiAdblockAttachmentState(siteHost: host, isEnabled: isEnabled)
    }
}

struct SumiAdblockRegionalListSelection: Codable, Equatable, Sendable {
    var identifiers: [String]

    static let empty = SumiAdblockRegionalListSelection(identifiers: [])
}

struct SumiAdBlockingAssets: Equatable, Sendable {
    static let empty = SumiAdBlockingAssets()

    let contentRuleListIdentifiers: [String]
    let scriptSources: [String]
    let scriptMessageHandlerNames: [String]

    init(
        contentRuleListIdentifiers: [String] = [],
        scriptSources: [String] = [],
        scriptMessageHandlerNames: [String] = []
    ) {
        self.contentRuleListIdentifiers = contentRuleListIdentifiers
        self.scriptSources = scriptSources
        self.scriptMessageHandlerNames = scriptMessageHandlerNames
    }

    var isEmpty: Bool {
        contentRuleListIdentifiers.isEmpty
            && scriptSources.isEmpty
            && scriptMessageHandlerNames.isEmpty
    }
}

struct SumiAdBlockingNormalTabDecision: Equatable, Sendable {
    let status: SumiAdBlockingModuleStatus
    let effectivePolicy: SumiAdblockEffectivePolicy
    let assets: SumiAdBlockingAssets
    let contentBlockingService: SumiContentBlockingService?

    static let disabled = SumiAdBlockingNormalTabDecision(
        status: .disabled,
        effectivePolicy: SumiAdblockEffectivePolicy(host: nil, isEnabled: false),
        assets: .empty,
        contentBlockingService: nil
    )

    var attachmentState: SumiAdblockAttachmentState {
        SumiAdblockAttachmentState(
            siteHost: effectivePolicy.host,
            isEnabled: effectivePolicy.isEnabled,
            hasEnhancedRuntime: assets.scriptSources.isEmpty == false
        )
    }

    static func == (lhs: SumiAdBlockingNormalTabDecision, rhs: SumiAdBlockingNormalTabDecision) -> Bool {
        lhs.status == rhs.status
            && lhs.effectivePolicy == rhs.effectivePolicy
            && lhs.assets == rhs.assets
            && (lhs.contentBlockingService == nil) == (rhs.contentBlockingService == nil)
    }
}

@MainActor
final class AdblockSettingsStore: ObservableObject {
    static let shared = AdblockSettingsStore()

    private enum DefaultsKey {
        static let autoUpdateEnabled = "settings.adblock.autoUpdateEnabled"
        static let cosmeticMode = "settings.adblock.cosmeticMode"
        static let regionalListSelection = "settings.adblock.regionalListSelection"
        static let selectedLists = "settings.adblock.selectedLists"
        static let selectedNativeProfile = "settings.adblock.selectedNativeProfile"
        static let listSelectionRequiresUpdate = "settings.adblock.listSelectionRequiresUpdate"
    }

    @Published var autoUpdateEnabled: Bool {
        didSet {
            userDefaults.set(autoUpdateEnabled, forKey: DefaultsKey.autoUpdateEnabled)
            changesSubject.send(())
        }
    }

    @Published var cosmeticMode: SumiAdblockCosmeticMode {
        didSet {
            userDefaults.set(cosmeticMode.rawValue, forKey: DefaultsKey.cosmeticMode)
            changesSubject.send(())
        }
    }

    @Published var regionalListSelection: SumiAdblockRegionalListSelection {
        didSet {
            if let data = try? JSONEncoder().encode(regionalListSelection) {
                userDefaults.set(data, forKey: DefaultsKey.regionalListSelection)
            }
            changesSubject.send(())
        }
    }

    @Published var selectedLists: SumiAdblockFilterListSelection {
        didSet {
            if let data = try? JSONEncoder().encode(selectedLists) {
                userDefaults.set(data, forKey: DefaultsKey.selectedLists)
            }
            listSelectionRequiresUpdate = true
            changesSubject.send(())
        }
    }

    @Published private(set) var selectedNativeProfile: AdblockFilterListProfileKind {
        didSet {
            userDefaults.set(selectedNativeProfile.rawValue, forKey: DefaultsKey.selectedNativeProfile)
            listSelectionRequiresUpdate = true
            changesSubject.send(())
        }
    }

    @Published private(set) var listSelectionRequiresUpdate: Bool {
        didSet {
            userDefaults.set(listSelectionRequiresUpdate, forKey: DefaultsKey.listSelectionRequiresUpdate)
        }
    }

    private let userDefaults: UserDefaults
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [
            DefaultsKey.autoUpdateEnabled: true,
            DefaultsKey.cosmeticMode: SumiAdblockCosmeticMode.nativeCSS.rawValue,
            DefaultsKey.selectedNativeProfile: AdblockFilterListProfileKind.currentDefault.rawValue,
        ])
        autoUpdateEnabled = userDefaults.object(forKey: DefaultsKey.autoUpdateEnabled) as? Bool ?? true
        cosmeticMode = userDefaults.string(forKey: DefaultsKey.cosmeticMode)
            .flatMap(SumiAdblockCosmeticMode.init(rawValue:))
            ?? .nativeCSS
        if let data = userDefaults.data(forKey: DefaultsKey.regionalListSelection),
           let decoded = try? JSONDecoder().decode(SumiAdblockRegionalListSelection.self, from: data) {
            regionalListSelection = decoded
        } else {
            regionalListSelection = .empty
        }
        if let data = userDefaults.data(forKey: DefaultsKey.selectedLists),
           let decoded = try? JSONDecoder().decode(SumiAdblockFilterListSelection.self, from: data) {
            selectedLists = decoded
        } else {
            selectedLists = .defaultSelection
        }
        selectedNativeProfile = userDefaults.string(forKey: DefaultsKey.selectedNativeProfile)
            .flatMap(AdblockFilterListProfileKind.init(storedIdentifier:))
            ?? .currentDefault
        listSelectionRequiresUpdate = userDefaults.object(forKey: DefaultsKey.listSelectionRequiresUpdate) as? Bool ?? false
    }

    func isListSelected(
        _ descriptor: AdblockFilterListDescriptor,
        registry: AdblockFilterListRegistry = AdblockFilterListRegistry()
    ) -> Bool {
        registry.validatedSelection(
            selectedLists,
            profileKind: selectedNativeProfile
        ).resolvedIdentifiers.contains(descriptor.id)
    }

    func setList(
        _ descriptor: AdblockFilterListDescriptor,
        isSelected: Bool,
        registry: AdblockFilterListRegistry = AdblockFilterListRegistry()
    ) {
        var identifiers = selectedLists.usesDefaultSelection
            ? registry.validatedSelection(
                selectedLists,
                profileKind: selectedNativeProfile
            ).resolvedIdentifiers
            : selectedLists.identifiers
        if isSelected {
            identifiers.append(descriptor.id)
        } else {
            identifiers.removeAll { $0 == descriptor.id }
        }
        identifiers = registry.validatedSelection(
            SumiAdblockFilterListSelection(identifiers: identifiers)
        ).resolvedIdentifiers
        selectedLists = SumiAdblockFilterListSelection(identifiers: identifiers)
    }

    func markListUpdateCompleted() {
        listSelectionRequiresUpdate = false
    }

    @discardableResult
    func setSelectedNativeProfile(
        _ profileKind: AdblockFilterListProfileKind,
        registry: AdblockFilterListRegistry = AdblockFilterListRegistry(),
        allowDeveloperOnly: Bool = false
    ) -> Bool {
        let profile = registry.profile(for: profileKind)
        guard allowDeveloperOnly || !profile.isDeveloperOnly else {
            return false
        }
        selectedNativeProfile = profileKind
        return true
    }
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

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(
        userDefaults: UserDefaults = .standard,
        registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver()
    ) {
        self.userDefaults = userDefaults
        self.siteNormalizer = SumiTrackingProtectionSiteNormalizer(registrableDomainResolver: registrableDomainResolver)
        siteOverrides = Self.loadSiteOverrides(from: userDefaults)
    }

    var sortedSiteOverrides: [(host: String, override: SumiAdblockSiteOverride)] {
        siteOverrides
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    func effectivePolicy(for url: URL?, globalEnabled: Bool) -> SumiAdblockEffectivePolicy {
        let host = normalizedHost(for: url)
        if let host, let override = siteOverrides[host] {
            switch override {
            case .allowed:
                return SumiAdblockEffectivePolicy(host: host, isEnabled: true)
            case .disabled:
                return SumiAdblockEffectivePolicy(host: host, isEnabled: false)
            case .inherit:
                break
            }
        }
        return SumiAdblockEffectivePolicy(host: host, isEnabled: globalEnabled)
    }

    func override(for url: URL?) -> SumiAdblockSiteOverride {
        guard let host = normalizedHost(for: url) else { return .inherit }
        return siteOverrides[host] ?? .inherit
    }

    func setSiteOverride(_ override: SumiAdblockSiteOverride, for url: URL?) {
        guard let host = normalizedHost(for: url) else { return }
        setSiteOverride(override, forNormalizedHost: host)
    }

    func setSiteOverride(_ override: SumiAdblockSiteOverride, forUserInput input: String) -> Bool {
        guard let host = siteNormalizer.normalizedHost(fromUserInput: input) else { return false }
        setSiteOverride(override, forNormalizedHost: host)
        return true
    }

    func removeSiteOverride(forNormalizedHost host: String) {
        setSiteOverride(.inherit, forNormalizedHost: host)
    }

    func normalizedHost(for url: URL?) -> String? {
        siteNormalizer.normalizedHost(for: url)
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
        persistSiteOverrides()
        changesSubject.send(())
    }

    private func persistSiteOverrides() {
        let encoded = siteOverrides.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        userDefaults.set(data, forKey: DefaultsKey.siteOverrides)
    }

    private static func loadSiteOverrides(from userDefaults: UserDefaults) -> [String: SumiAdblockSiteOverride] {
        guard let data = userDefaults.data(forKey: DefaultsKey.siteOverrides),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded.reduce(into: [:]) { result, entry in
            guard let override = SumiAdblockSiteOverride(rawValue: entry.value),
                  override != .inherit
            else { return }
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
    private let settingsStore: AdblockSettingsStore
    private let isAdblockEnabled: @Sendable () async -> Bool
    let configuredNativeCompilerIdentity: NativeContentBlockingCompilerIdentity
    private var settingsCancellable: AnyCancellable?
    private(set) var lastFailedShardIdentifier: String?

    var hasActiveGeneration: Bool {
        ruleListProvider.activeManifest != nil
    }

    var activeEnhancedRuntimeBundle: AdblockEnhancedRuntimeBundle? {
        ruleListProvider.activeManifest?.enhancedRuntimeBundle
    }

    var activeManifest: AdblockCompiledGenerationManifest? {
        ruleListProvider.activeManifest
    }

    init(
        settingsStore: AdblockSettingsStore,
        isAdblockEnabled: @escaping @Sendable () async -> Bool = { true },
        registry: AdblockFilterListRegistry = AdblockFilterListRegistry(),
        manifestStore: AdblockUpdateManifestStore = AdblockUpdateManifestStore(),
        nativeCompiler: (any NativeContentBlockingCompiler)? = nil,
        enhancedCompiler: (any EnhancedCompatibilityCompiler)? = nil,
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler(),
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging = AdblockRetainingCompiledRuleListCatalog()
    ) {
        self.manifestStore = manifestStore
        self.isAdblockEnabled = isAdblockEnabled
        self.settingsStore = settingsStore
        let rustCompiler = AdblockRustCompiler()
        let resolvedNativeCompiler = nativeCompiler ?? rustCompiler
        let resolvedEnhancedCompiler = enhancedCompiler ?? rustCompiler
        configuredNativeCompilerIdentity = resolvedNativeCompiler.identity
        let provider = AdblockManifestRuleListProvider(
            manifest: nil,
            cosmeticMode: settingsStore.cosmeticMode
        )
        ruleListProvider = provider
        contentBlockingService = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            ruleListProvider: provider,
            compiledRuleListCatalog: compiledRuleListCatalog
        )
        let publisher = AdblockRuleListPublisher(
            ruleListProvider: provider,
            contentBlockingService: contentBlockingService
        )
        updateCoordinator = AdblockUpdateCoordinator.production(
            registry: registry,
            selection: { await MainActor.run { settingsStore.selectedLists } },
            nativeProfileSelection: { await MainActor.run { settingsStore.selectedNativeProfile } },
            isAdblockEnabled: isAdblockEnabled,
            manifestStore: manifestStore,
            nativeCompiler: resolvedNativeCompiler,
            enhancedCompiler: resolvedEnhancedCompiler,
            publisher: publisher,
            contentRuleListStore: compiler,
            garbageCollector: AdblockGenerationGarbageCollector(
                manifestStore: manifestStore,
                contentRuleListStore: compiler
            )
        )
        Task { [weak self] in
            guard let self else { return }
            await self.loadActiveManifestIfEnabled()
            _ = await self.updateCoordinator.rollbackIfActiveGenerationFailsSmokeCheck()
        }
        settingsCancellable = settingsStore.$cosmeticMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] cosmeticMode in
                self?.ruleListProvider.updateCosmeticMode(cosmeticMode)
            }
    }

    static func ruleListIdentifiers(for cosmeticMode: SumiAdblockCosmeticMode) -> [String] {
        AdblockManifestRuleListProvider.attachedGroupKinds(for: cosmeticMode)
            .map(\.rawValue)
            .sorted()
    }

    func requestManualUpdate() async throws -> AdblockCompiledGenerationManifest? {
        guard await isAdblockEnabled() else { return nil }
        do {
            let manifest = try await updateCoordinator.updateIfEnabled(reason: "manual")
            if manifest != nil {
                lastFailedShardIdentifier = nil
                settingsStore.markListUpdateCompleted()
            }
            return manifest
        } catch let diagnostics as AdblockUpdateDiagnostics {
            lastFailedShardIdentifier = diagnostics.failedShardIdentifier
            throw diagnostics
        }
    }

    func loadActiveManifestIfEnabled() async {
        guard await isAdblockEnabled() else { return }
        do {
            let manifest = try await manifestStore.activeManifest()
            let definitions: [SumiContentRuleListDefinition]
            if let manifest {
                definitions = try await manifestStore.compiledShardDefinitions(for: manifest)
            } else {
                definitions = []
            }
            ruleListProvider.updateManifest(manifest, compiledDefinitions: definitions)
            lastFailedShardIdentifier = nil
        } catch let diagnostics as AdblockUpdateDiagnostics {
            lastFailedShardIdentifier = diagnostics.failedShardIdentifier
            ruleListProvider.updateManifest(nil)
        } catch {
            lastFailedShardIdentifier = "manifest-load"
            ruleListProvider.updateManifest(nil)
        }
    }

    func requestInitialUpdateIfNeeded() {
        guard ruleListProvider.activeManifest == nil
        else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                await self.loadActiveManifestIfEnabled()
                guard await MainActor.run(body: { self.ruleListProvider.activeManifest == nil }) else {
                    return
                }
                _ = try await self.updateCoordinator.updateIfEnabled(reason: "initial")
                await MainActor.run {
                    self.lastFailedShardIdentifier = nil
                }
            } catch let diagnostics as AdblockUpdateDiagnostics {
                await MainActor.run {
                    self.lastFailedShardIdentifier = diagnostics.failedShardIdentifier
                }
            } catch {}
        }
    }

    static let tinyFixtureFilters = [
        "||ads.example.test^",
        "##.ad-banner",
        "example.test##.sponsored",
        "example.test###sponsor.card[data-ad=\"1\"]",
    ]
}

@MainActor
final class AdblockRetainingCompiledRuleListCatalog: SumiCompiledContentRuleListCataloging {
    func staleIdentifiers(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        []
    }

    func forgetIdentifiers(_ identifiers: [String]) {}
}

@MainActor
final class SumiAdBlockingModule {
    static let shared = SumiAdBlockingModule()

    private let moduleRegistry: SumiModuleRegistry
    private let settingsFactory: @MainActor () -> AdblockSettingsStore
    private let sitePolicyFactory: @MainActor () -> AdblockSitePolicyStore
    private let ruleListStoreFactory: @MainActor (AdblockSettingsStore, @escaping @Sendable () async -> Bool) -> AdblockWebKitRuleListStore
    private var cachedSettingsStore: AdblockSettingsStore?
    private var cachedSitePolicyStore: AdblockSitePolicyStore?
    private var cachedRuleListStore: AdblockWebKitRuleListStore?

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        settingsFactory: @escaping @MainActor () -> AdblockSettingsStore = { .shared },
        sitePolicyFactory: @escaping @MainActor () -> AdblockSitePolicyStore = { .shared },
        ruleListStoreFactory: @escaping @MainActor (AdblockSettingsStore, @escaping @Sendable () async -> Bool) -> AdblockWebKitRuleListStore = {
            AdblockWebKitRuleListStore(settingsStore: $0, isAdblockEnabled: $1)
        }
    ) {
        self.moduleRegistry = moduleRegistry
        self.settingsFactory = settingsFactory
        self.sitePolicyFactory = sitePolicyFactory
        self.ruleListStoreFactory = ruleListStoreFactory
    }

    var isEnabled: Bool {
        moduleRegistry.isEnabled(.adBlocking)
    }

    var status: SumiAdBlockingModuleStatus {
        isEnabled ? .enabledNativeContentBlocking : .disabled
    }

    var hasLoadedRuntime: Bool {
        cachedRuleListStore != nil
    }

    func setEnabled(_ isEnabled: Bool) {
        moduleRegistry.setEnabled(isEnabled, for: .adBlocking)
        if !isEnabled {
            cachedRuleListStore?.contentBlockingService.setPolicy(.disabled)
            cachedRuleListStore = nil
        }
    }

    func assetsIfAvailable() -> SumiAdBlockingAssets {
        guard isEnabled else { return .empty }
        return SumiAdBlockingAssets(
            contentRuleListIdentifiers: contentRuleListIdentifiers()
        )
    }

    func normalTabDecision(for url: URL?) -> SumiAdBlockingNormalTabDecision {
        guard isEnabled else {
            return SumiAdBlockingNormalTabDecision(
                status: .disabled,
                effectivePolicy: effectivePolicy(for: url),
                assets: .empty,
                contentBlockingService: nil
            )
        }
        let policy = sitePolicyStoreIfEnabled().effectivePolicy(for: url, globalEnabled: true)
        guard policy.isEnabled else {
            return SumiAdBlockingNormalTabDecision(
                status: status,
                effectivePolicy: policy,
                assets: .empty,
                contentBlockingService: nil
            )
        }
        return SumiAdBlockingNormalTabDecision(
            status: status,
            effectivePolicy: policy,
            assets: assetsForNormalTab(url: url),
            contentBlockingService: ruleListStoreIfEnabled().contentBlockingService
        )
    }

    func normalTabEnhancedRuntimeScripts(for url: URL?) -> [SumiUserScript] {
        guard isEnabled,
              SumiAdblockEnhancedRuntime.isEligibleWebURL(url),
              let settings = settingsIfEnabled(),
              settings.cosmeticMode == .enhancedRuntime
        else { return [] }

        let policy = sitePolicyStoreIfEnabled().effectivePolicy(for: url, globalEnabled: true)
        guard policy.isEnabled else { return [] }

        let ruleListStore = ruleListStoreIfEnabled()
        guard ruleListStore.hasActiveGeneration,
              let bundle = ruleListStore.activeEnhancedRuntimeBundle,
              let script = SumiAdblockEnhancedRuntime.makeScript(
                bundle: bundle,
                pageURL: url
              )
        else { return [] }

        return [script]
    }

    func normalizedSiteHost(for url: URL?) -> String? {
        sitePolicyStoreIfEnabled().normalizedHost(for: url)
    }

    func effectivePolicy(for url: URL?) -> SumiAdblockEffectivePolicy {
        let store = sitePolicyStoreIfEnabled()
        guard isEnabled else {
            return SumiAdblockEffectivePolicy(
                host: store.normalizedHost(for: url),
                isEnabled: false
            )
        }
        return store.effectivePolicy(for: url, globalEnabled: true)
    }

    func desiredAttachmentState(for url: URL?) -> SumiAdblockAttachmentState {
        guard isEnabled else {
            return effectivePolicy(for: url).attachmentState
        }
        return normalTabDecision(for: url).attachmentState
    }

    func attachmentDiagnostics(for url: URL?) -> SumiAdblockAttachmentDiagnostics {
        let policy = effectivePolicy(for: url)
        let siteOverride = sitePolicyStoreIfEnabled().override(for: url)
        guard isEnabled, policy.isEnabled else {
            let settings = cachedSettingsStore ?? settingsFactory()
            return SumiAdblockAttachmentDiagnostics(
                siteHost: policy.host,
                globalAdblockEnabled: isEnabled,
                sitePolicyAllowsAdblock: policy.isEnabled,
                siteOverride: siteOverride,
                isEnabled: policy.isEnabled,
                hasActiveGeneration: false,
                attachedNativeGroups: [],
                attachedShardIdentifiers: [],
                contentRuleListIdentifiers: [],
                selectedListIdentifiers: [],
                selectedNativeProfile: settings.selectedNativeProfile,
                nativeCompiler: nil,
                nativeCompilationSummary: nil,
                nativeSourceLists: [],
                networkShardCount: 0,
                nativeCSSShardCount: 0,
                totalNetworkRuleCount: 0,
                totalNativeCSSRuleCount: 0,
                largestShardJSONByteCount: 0,
                failedShardIdentifier: nil,
                cosmeticMode: settings.cosmeticMode,
                enhancedRuntimeIsEnabled: false,
                trackingProtectionModuleEnabled: moduleRegistry.isEnabled(.trackingProtection),
                generationIsStale: settings.listSelectionRequiresUpdate
            )
        }

        let settings = settingsIfEnabled()
        let manifest = ruleListStoreIfEnabled().activeManifest
        let allowedGroups = AdblockManifestRuleListProvider.attachedGroupKinds(
            for: settings?.cosmeticMode ?? .nativeCSS
        )
        let attachedShards = manifest?.allNativeShards
            .filter { allowedGroups.contains($0.kind) }
            ?? []
        let attachedGroups = Array(Set(attachedShards.map(\.kind)))
            .sorted { $0.rawValue < $1.rawValue }
        let attachedShardIdentifiers = attachedShards
            .map(\.webKitIdentifier)
            .sorted()
        let allShards = manifest?.allNativeShards ?? []
        let networkShards = manifest?.networkShards ?? []
        let nativeCSSShards = manifest?.nativeCSSShards ?? []

        return SumiAdblockAttachmentDiagnostics(
            siteHost: policy.host,
            globalAdblockEnabled: true,
            sitePolicyAllowsAdblock: policy.isEnabled,
            siteOverride: siteOverride,
            isEnabled: true,
            hasActiveGeneration: manifest != nil,
            attachedNativeGroups: attachedGroups,
            attachedShardIdentifiers: attachedShardIdentifiers,
            contentRuleListIdentifiers: attachedShardIdentifiers.isEmpty
                ? contentRuleListIdentifiers()
                : attachedShardIdentifiers,
            selectedListIdentifiers: manifest?.selectedFilterLists.map(\.id).sorted() ?? [],
            selectedNativeProfile: manifest?.nativeProfile,
            nativeCompiler: manifest?.nativeCompiler,
            nativeCompilationSummary: manifest?.nativeCompilationSummary,
            nativeSourceLists: manifest?.nativeCompilerSourceLists ?? [],
            networkShardCount: networkShards.count,
            nativeCSSShardCount: nativeCSSShards.count,
            totalNetworkRuleCount: networkShards.reduce(0) { $0 + $1.approximateRuleCount },
            totalNativeCSSRuleCount: nativeCSSShards.reduce(0) { $0 + $1.approximateRuleCount },
            largestShardJSONByteCount: allShards.map(\.jsonByteCount).max() ?? 0,
            failedShardIdentifier: ruleListStoreIfEnabled().lastFailedShardIdentifier,
            cosmeticMode: settings?.cosmeticMode,
            enhancedRuntimeIsEnabled: settings?.cosmeticMode == .enhancedRuntime,
            trackingProtectionModuleEnabled: moduleRegistry.isEnabled(.trackingProtection),
            generationIsStale: (settings?.listSelectionRequiresUpdate ?? false)
                || manifest?.nativeProfile != settings?.selectedNativeProfile
                || manifest?.nativeCompiler != ruleListStoreIfEnabled().configuredNativeCompilerIdentity
        )
    }

    func attachmentDiagnosticsReport(for url: URL?) -> String {
        attachmentDiagnostics(for: url).developerReport
    }

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
        if let cachedSettingsStore {
            return cachedSettingsStore
        }
        let settings = settingsFactory()
        cachedSettingsStore = settings
        return settings
    }

    func sitePolicyStoreIfEnabled() -> AdblockSitePolicyStore {
        if let cachedSitePolicyStore {
            return cachedSitePolicyStore
        }
        let store = sitePolicyFactory()
        cachedSitePolicyStore = store
        return store
    }

    private func ruleListStoreIfEnabled() -> AdblockWebKitRuleListStore {
        if let cachedRuleListStore {
            return cachedRuleListStore
        }
        let settings = settingsIfEnabled() ?? settingsFactory()
        let store = ruleListStoreFactory(settings, { [weak self] in
            await MainActor.run { self?.isEnabled == true }
        })
        cachedRuleListStore = store
        store.requestInitialUpdateIfNeeded()
        return store
    }

    private func contentRuleListIdentifiers() -> [String] {
        guard let settings = settingsIfEnabled() else { return [] }
        if let manifest = cachedRuleListStore?.activeManifest {
            let allowedKinds = AdblockManifestRuleListProvider.attachedGroupKinds(
                for: settings.cosmeticMode
            )
            return manifest.allNativeShards
                .filter { allowedKinds.contains($0.kind) }
                .map(\.webKitIdentifier)
                .sorted()
        }
        return AdblockWebKitRuleListStore.ruleListIdentifiers(for: settings.cosmeticMode)
    }

    private func assetsForNormalTab(url: URL?) -> SumiAdBlockingAssets {
        let enhancedScripts = normalTabEnhancedRuntimeScripts(for: url)
        return SumiAdBlockingAssets(
            contentRuleListIdentifiers: contentRuleListIdentifiers(),
            scriptSources: enhancedScripts.map(\.source),
            scriptMessageHandlerNames: enhancedScripts.flatMap(\.messageNames)
        )
    }
}
