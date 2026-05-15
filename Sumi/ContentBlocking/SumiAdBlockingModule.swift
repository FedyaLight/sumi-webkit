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
            return "Network blocking only."
        case .nativeCSS:
            return "Allows WebKit content blocker CSS hiding rules."
        case .enhancedRuntime:
            return "Reserved for future runtime cleanup; no scripts are loaded yet."
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
    let assets: SumiAdBlockingAssets
    let contentBlockingService: SumiContentBlockingService?

    static let disabled = SumiAdBlockingNormalTabDecision(
        status: .disabled,
        assets: .empty,
        contentBlockingService: nil
    )

    static func == (lhs: SumiAdBlockingNormalTabDecision, rhs: SumiAdBlockingNormalTabDecision) -> Bool {
        lhs.status == rhs.status
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
    static let fixtureSourceIdentifier = "SumiAdblockTinyFixture"

    let contentBlockingService: SumiContentBlockingService
    private let filterCompiler: AdblockFilterCompiling
    private let filterSource: () -> [String]
    private var settingsCancellable: AnyCancellable?
    private var compilationGeneration = 0
    private(set) var latestCompilationOutput: AdblockCompilationOutput?

    init(
        settingsStore: AdblockSettingsStore,
        filterCompiler: AdblockFilterCompiling = AdblockRustCompiler(),
        filterSource: @escaping () -> [String] = { AdblockWebKitRuleListStore.tinyFixtureFilters },
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler(),
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging = AdblockRetainingCompiledRuleListCatalog()
    ) {
        self.filterCompiler = filterCompiler
        self.filterSource = filterSource
        contentBlockingService = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            compiledRuleListCatalog: compiledRuleListCatalog
        )
        scheduleCompilation(for: settingsStore.cosmeticMode)
        settingsCancellable = settingsStore.$cosmeticMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] cosmeticMode in
                self?.scheduleCompilation(for: cosmeticMode)
            }
    }

    static func ruleListIdentifiers(for cosmeticMode: SumiAdblockCosmeticMode) -> [String] {
        outputGroups(for: cosmeticMode).map { group in
            switch group {
            case .network:
                return "\(fixtureSourceIdentifier).network"
            case .nativeCosmeticCSS:
                return "\(fixtureSourceIdentifier).native-css"
            }
        }
        .sorted()
    }

    private func scheduleCompilation(for cosmeticMode: SumiAdblockCosmeticMode) {
        compilationGeneration += 1
        let generation = compilationGeneration
        let input = AdblockCompilationInput(
            sourceIdentifier: Self.fixtureSourceIdentifier,
            filterTexts: filterSource(),
            selectedOutputGroups: Self.outputGroups(for: cosmeticMode)
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let output = try await self.filterCompiler.compile(input)
                guard generation == self.compilationGeneration else { return }
                self.latestCompilationOutput = output
                self.contentBlockingService.setPolicy(.enabled(ruleLists: output.ruleListDefinitions))
            } catch {
                guard generation == self.compilationGeneration else { return }
                self.latestCompilationOutput = nil
                self.contentBlockingService.setPolicy(.disabled)
            }
        }
    }

    private static func outputGroups(for cosmeticMode: SumiAdblockCosmeticMode) -> Set<AdblockCompiledRuleGroupKind> {
        switch cosmeticMode {
        case .off:
            return [.network]
        case .nativeCSS, .enhancedRuntime:
            return [.network, .nativeCosmeticCSS]
        }
    }

    static let tinyFixtureFilters = [
        "||sumi-adblock-test-blocked.example^",
        "||sumi-adblock-domain-test.example^$domain=example.com",
        "example.com##.sumi-adblock-test-hide",
        "example.com##+js(sumi-future-scriptlet)",
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
    private let ruleListStoreFactory: @MainActor (AdblockSettingsStore) -> AdblockWebKitRuleListStore
    private var cachedSettingsStore: AdblockSettingsStore?
    private var cachedSitePolicyStore: AdblockSitePolicyStore?
    private var cachedRuleListStore: AdblockWebKitRuleListStore?

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        settingsFactory: @escaping @MainActor () -> AdblockSettingsStore = { .shared },
        sitePolicyFactory: @escaping @MainActor () -> AdblockSitePolicyStore = { .shared },
        ruleListStoreFactory: @escaping @MainActor (AdblockSettingsStore) -> AdblockWebKitRuleListStore = {
            AdblockWebKitRuleListStore(settingsStore: $0)
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
            return .disabled
        }
        let policy = sitePolicyStoreIfEnabled().effectivePolicy(for: url, globalEnabled: true)
        guard policy.isEnabled else {
            return SumiAdBlockingNormalTabDecision(
                status: status,
                assets: .empty,
                contentBlockingService: nil
            )
        }
        return SumiAdBlockingNormalTabDecision(
            status: status,
            assets: assetsIfAvailable(),
            contentBlockingService: ruleListStoreIfEnabled().contentBlockingService
        )
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
        let store = ruleListStoreFactory(settingsIfEnabled() ?? settingsFactory())
        cachedRuleListStore = store
        return store
    }

    private func contentRuleListIdentifiers() -> [String] {
        guard let settings = settingsIfEnabled() else { return [] }
        return AdblockWebKitRuleListStore.ruleListIdentifiers(for: settings.cosmeticMode)
    }
}
