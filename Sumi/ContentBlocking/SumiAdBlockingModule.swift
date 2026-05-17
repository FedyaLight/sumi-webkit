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

struct SumiAdblockSurfaceEligibility: Equatable, Sendable {
    let isEligible: Bool
    let normalizedSiteHost: String?
    let ineligibleReason: String?

    static func evaluate(
        url: URL?,
        normalizer: SumiTrackingProtectionSiteNormalizer
    ) -> SumiAdblockSurfaceEligibility {
        guard let url else {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "No URL"
            )
        }

        let scheme = url.scheme?.lowercased()
        if SumiSurface.isEmptyNewTabURL(url) || scheme == "about" {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "Sumi empty/new tab surface"
            )
        }
        if scheme == "sumi" {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "Internal Sumi surface"
            )
        }
        if scheme == "file" {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "Local file URL"
            )
        }
        guard scheme == "http" || scheme == "https" else {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "Unsupported URL scheme: \(scheme ?? "nil")"
            )
        }
        guard let host = normalizer.normalizedHost(for: url) else {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "No normalized web host"
            )
        }
        return SumiAdblockSurfaceEligibility(
            isEligible: true,
            normalizedSiteHost: host,
            ineligibleReason: nil
        )
    }
}

struct SumiAdblockAttachmentState: Equatable, Sendable {
    let siteHost: String?
    let isEnabled: Bool
    let hasEnhancedRuntime: Bool
    let attachedShardIdentifiers: [String]

    init(
        siteHost: String?,
        isEnabled: Bool,
        hasEnhancedRuntime: Bool = false,
        attachedShardIdentifiers: [String] = []
    ) {
        self.siteHost = siteHost
        self.isEnabled = isEnabled
        self.hasEnhancedRuntime = hasEnhancedRuntime
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
    let attachedNativeGroups: [AdblockCompiledRuleGroupKind]
    let attachedShardIdentifiers: [String]
    let expectedNetworkShardIdentifiers: [String]
    let expectedNativeCSSShardIdentifiers: [String]
    let missingShardIdentifiers: [String]
    let contentRuleListIdentifiers: [String]
    let selectedListIdentifiers: [String]
    let activeManifestListIdentifiers: [String]
    let compilerDiagnosticsSummary: String?
    let selectedNativeProfile: AdblockFilterListProfileKind?
    let activeCompiledNativeProfile: AdblockFilterListProfileKind?
    let selectedProfileDiffersFromActiveGeneration: Bool
    let activeGenerationId: String?
    let previousGenerationId: String?
    let previousGenerationRetained: Bool
    let lastSuccessfulUpdateDate: Date?
    let nativeCompiler: NativeContentBlockingCompilerIdentity?
    let nativeCompilationSummary: NativeContentBlockingCompilationSummary?
    let nativeSourceLists: [NativeContentBlockingSourceList]
    let generationSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
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
    let lastUpdateSummary: String?
    let lastUpdateError: String?
    let lastUpdateFailureStage: AdblockUpdateFailureStage?
    let lastUpdateListStatuses: [AdblockFilterListUpdateStatus]
    let effectiveSelectionDiagnostics: AdblockEffectiveSelectionDiagnostics?
    let latestRebuildMemoryDiagnostics: AdblockRebuildMemoryDiagnostics?
    let currentProcessResidentMemoryBytes: UInt64?
    let unsafeNativeCSSFilteredRuleCount: Int
    let ineligibleSurfaceReason: String?
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
            "activeCompiledNativeProfile=\(activeCompiledNativeProfile?.rawValue ?? "nil")",
            "selectedProfileDiffersFromActiveGeneration=\(selectedProfileDiffersFromActiveGeneration)",
            "activeGenerationId=\(activeGenerationId ?? "nil")",
            "previousGenerationId=\(previousGenerationId ?? "nil")",
            "previousGenerationRetained=\(previousGenerationRetained)",
            "lastSuccessfulUpdateDate=\(lastSuccessfulUpdateDate?.description ?? "nil")",
            "lastUpdateSummary=\(lastUpdateSummary ?? "nil")",
            "lastUpdateError=\(lastUpdateError ?? "nil")",
            "nativeCompiler=\(nativeCompiler.map { "\($0.name) \($0.version)" } ?? "nil")",
            "generationSource=\(generationSource?.rawValue ?? "nil")",
            "nativeRuleBundleId=\(nativeRuleBundleId ?? "nil")",
            "bundleProfileId=\(bundleProfileId ?? "nil")",
            "activeGeneration=\(hasActiveGeneration)",
            "generationIsStale=\(generationIsStale)",
            "lastInstallSummary=\(lastUpdateSummary ?? "nil")",
            "lastInstallError=\(lastUpdateError ?? "nil")",
            "lastInstallFailureStage=\(lastUpdateFailureStage?.rawValue ?? "nil")",
            "selectedListIDs=\(selectedListIdentifiers.joined(separator: ","))",
            "effectiveMode=\(effectiveSelectionDiagnostics?.effectiveModeLabel ?? "nil")",
            "usesProfileDerivedSelection=\(effectiveSelectionDiagnostics?.usesProfileDerivedSelection.description ?? "nil")",
            "manualSelectedListIDs=\(effectiveSelectionDiagnostics?.manuallySelectedListIdentifiers.joined(separator: ",") ?? "nil")",
            "profileDerivedListIDs=\(effectiveSelectionDiagnostics?.profileDerivedListIdentifiers.joined(separator: ",") ?? "nil")",
            "finalEffectiveListIDs=\(effectiveSelectionDiagnostics?.finalEffectiveListIdentifiers.joined(separator: ",") ?? "nil")",
            "conflictDroppedListIDs=\(effectiveSelectionDiagnostics?.droppedConflictingIdentifiers.joined(separator: ",") ?? "nil")",
            "activeManifestListIDs=\(activeManifestListIdentifiers.joined(separator: ","))",
            "compilerDiagnosticsSummary=\(compilerDiagnosticsSummary ?? "nil")",
            "lastUpdateFailureStage=\(lastUpdateFailureStage?.rawValue ?? "nil")",
            "networkShardCount=\(networkShardCount)",
            "nativeCSSShardCount=\(nativeCSSShardCount)",
            "attachedGroups=\(attachedNativeGroups.map(\.rawValue).joined(separator: ","))",
            "expectedNetworkShardIdentifiers=\(expectedNetworkShardIdentifiers.joined(separator: ","))",
            "expectedNativeCSSShardIdentifiers=\(expectedNativeCSSShardIdentifiers.joined(separator: ","))",
            "attachedShardIdentifiers=\(attachedShardIdentifiers.joined(separator: ","))",
            "missingShardIdentifiers=\(missingShardIdentifiers.joined(separator: ","))",
            "totalNetworkRuleCount=\(totalNetworkRuleCount)",
            "totalNativeCSSRuleCount=\(totalNativeCSSRuleCount)",
            "largestShardJSONByteCount=\(largestShardJSONByteCount)",
            "failedShardIdentifier=\(failedShardIdentifier ?? "nil")",
            "ruleCapHit=\(nativeCompilationSummary?.ruleCap.wasHit.description ?? "nil")",
            "discardedRuleCount=\(nativeCompilationSummary?.ruleCap.discardedRuleCount.description ?? "nil")",
            "unsafeNativeCSSFilteredRuleCount=\(unsafeNativeCSSFilteredRuleCount)",
            "rebuildPeakResidentMemoryBytes=\(latestRebuildMemoryDiagnostics?.peakResidentMemoryBytes.map(String.init) ?? "nil")",
            "rebuildSteadyStateResidentMemoryBytes=\(latestRebuildMemoryDiagnostics?.steadyStateResidentMemoryBytes.map(String.init) ?? "nil")",
            "rebuildMemoryStages=\(latestRebuildMemoryDiagnostics?.snapshots.map { "\($0.stage.rawValue):\($0.residentMemoryBytes)" }.joined(separator: ",") ?? "nil")",
            "rebuildBudgetWarnings=\(latestRebuildMemoryDiagnostics?.budgetWarnings.joined(separator: " | ") ?? "nil")",
            "currentProcessResidentMemoryBytes=\(currentProcessResidentMemoryBytes.map(String.init) ?? "nil")",
            "trackingProtectionEnabled=\(trackingProtectionModuleEnabled)",
            "cosmeticMode=\(cosmeticMode?.rawValue ?? "nil")",
            "enhancedRuntimeEnabled=\(enhancedRuntimeIsEnabled)",
            "ineligibleSurfaceReason=\(ineligibleSurfaceReason ?? "nil")",
            "lastUpdateListStatuses=\(lastUpdateListStatuses.map { "\($0.listIdentifier):\($0.failureStage?.rawValue ?? "ok"):\($0.httpStatus.map(String.init) ?? "nil"):\($0.rawByteSize.map(String.init) ?? "nil")" }.joined(separator: ","))",
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
    let selectedNativeProfile: AdblockFilterListProfileKind?
    let activeCompiledNativeProfile: AdblockFilterListProfileKind?
    let cosmeticMode: SumiAdblockCosmeticMode?
    let expectedNetworkShardIdentifiers: [String]
    let expectedNativeCSSShardIdentifiers: [String]
    let recordedAppliedShardIdentifiers: [String]
    let actualAttachedShardIdentifiers: [String]
    let attachedNetworkShardIdentifiers: [String]
    let attachedNativeCSSShardIdentifiers: [String]
    let missingShardIdentifiers: [String]
    let unexpectedOldShardIdentifiers: [String]
    let attachedGenerationIds: [String]
    let attachedGenerationId: String?
    let tabUsesActiveGeneration: Bool
    let tabAppearsToUseOlderGeneration: Bool
    let hasMixedGenerationAttachment: Bool
    let attachedWhilePerSiteAdblockDisabled: Bool
    let nativeCSSAttachedWhileCosmeticModeOff: Bool
    let reloadRequiredForActiveGeneration: Bool
    let attachmentAssessment: String
    let suspectedBlankPageCategory: String
    let attachmentMemorySnapshot: AdblockRebuildMemorySnapshot?
    let ineligibleSurfaceReason: String?
}

extension SumiAdblockCurrentTabDiagnostics {
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
            "selectedNativeProfile=\(selectedNativeProfile?.rawValue ?? "nil")",
            "activeCompiledNativeProfile=\(activeCompiledNativeProfile?.rawValue ?? "nil")",
            "cosmeticMode=\(cosmeticMode?.rawValue ?? "nil")",
            "expectedNetworkShardIdentifiers=\(expectedNetworkShardIdentifiers.joined(separator: ","))",
            "expectedNativeCSSShardIdentifiers=\(expectedNativeCSSShardIdentifiers.joined(separator: ","))",
            "recordedAppliedShardIdentifiers=\(recordedAppliedShardIdentifiers.joined(separator: ","))",
            "actualAttachedShardIdentifiers=\(actualAttachedShardIdentifiers.joined(separator: ","))",
            "attachedNetworkShardIdentifiers=\(attachedNetworkShardIdentifiers.joined(separator: ","))",
            "attachedNativeCSSShardIdentifiers=\(attachedNativeCSSShardIdentifiers.joined(separator: ","))",
            "missingShardIdentifiers=\(missingShardIdentifiers.joined(separator: ","))",
            "unexpectedOldShardIdentifiers=\(unexpectedOldShardIdentifiers.joined(separator: ","))",
            "attachedGenerationIds=\(attachedGenerationIds.joined(separator: ","))",
            "attachedGenerationId=\(attachedGenerationId ?? "nil")",
            "tabUsesActiveGeneration=\(tabUsesActiveGeneration)",
            "tabAppearsToUseOlderGeneration=\(tabAppearsToUseOlderGeneration)",
            "hasMixedGenerationAttachment=\(hasMixedGenerationAttachment)",
            "attachedWhilePerSiteAdblockDisabled=\(attachedWhilePerSiteAdblockDisabled)",
            "nativeCSSAttachedWhileCosmeticModeOff=\(nativeCSSAttachedWhileCosmeticModeOff)",
            "reloadRequiredForActiveGeneration=\(reloadRequiredForActiveGeneration)",
            "attachmentAssessment=\(attachmentAssessment)",
            "suspectedBlankPageCategory=\(suspectedBlankPageCategory)",
            "afterPageReloadAttachmentResidentMemoryBytes=\(attachmentMemorySnapshot?.residentMemoryBytes.description ?? "nil")",
            "ineligibleSurfaceReason=\(ineligibleSurfaceReason ?? "nil")",
        ].joined(separator: "\n")
    }
}

enum SumiAdblockBlankPageDiagnosticClassifier {
    static func classify(
        adblockOffVisible: Bool,
        networkOnlyVisible: Bool,
        nativeCSSVisible: Bool
    ) -> String {
        if adblockOffVisible, networkOnlyVisible, !nativeCSSVisible {
            return "suspected native CSS over-hide"
        }
        if adblockOffVisible, !networkOnlyVisible {
            return "suspected network overblocking"
        }
        if !adblockOffVisible {
            return "page blank without Adblock"
        }
        if nativeCSSVisible {
            return "no blank page reproduced"
        }
        return "inconclusive"
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
            hasEnhancedRuntime: assets.scriptSources.isEmpty == false,
            attachedShardIdentifiers: assets.contentRuleListIdentifiers
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
            DefaultsKey.cosmeticMode: SumiAdblockCosmeticMode.off.rawValue,
            DefaultsKey.selectedNativeProfile: AdblockFilterListProfileKind.currentDefault.rawValue,
        ])
        autoUpdateEnabled = userDefaults.object(forKey: DefaultsKey.autoUpdateEnabled) as? Bool ?? true
        cosmeticMode = userDefaults.string(forKey: DefaultsKey.cosmeticMode)
            .flatMap(SumiAdblockCosmeticMode.init(rawValue:))
            ?? .off
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
            .flatMap(AdblockFilterListProfileKind.init(rawValue:))
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

    func resetListsToSelectedProfile() {
        selectedLists = .defaultSelection
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
        guard let host else {
            return SumiAdblockEffectivePolicy(host: nil, isEnabled: false)
        }
        if let override = siteOverrides[host] {
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
    private let embeddedBundleURLProvider: @MainActor () -> URL?
    let configuredNativeCompilerIdentity: NativeContentBlockingCompilerIdentity
    private var settingsCancellable: AnyCancellable?
    private(set) var lastFailedShardIdentifier: String?
    private(set) var lastUpdateDiagnostics: AdblockUpdateDiagnostics?

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
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging = AdblockRetainingCompiledRuleListCatalog(),
        embeddedBundleURLProvider: @escaping @MainActor () -> URL? = {
            SumiAdblockNativeRuleBundle.bundledDirectoryURL(
                for: SumiProtectionBundleProfile.adblock
            ) ?? SumiAdblockNativeRuleBundle.bundledDirectoryURL()
        }
    ) {
        self.manifestStore = manifestStore
        self.isAdblockEnabled = isAdblockEnabled
        self.settingsStore = settingsStore
        self.embeddedBundleURLProvider = embeddedBundleURLProvider
        let rustCompiler = AdblockRustCompiler()
        let resolvedNativeCompiler = nativeCompiler ?? rustCompiler
        let resolvedEnhancedCompiler = enhancedCompiler ?? rustCompiler
        configuredNativeCompilerIdentity = resolvedNativeCompiler.identity
        let provider = AdblockManifestRuleListProvider(
            manifest: nil,
            cosmeticMode: settingsStore.cosmeticMode,
            compiledDefinitionLoader: AdblockManifestRuleListProvider.diskBackedDefinitionLoader(
                storageRoot: manifestStore.storageRoot
            )
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
            lastUpdateDiagnostics = await updateCoordinator.latestDiagnosticsSnapshot()
            if manifest != nil {
                lastFailedShardIdentifier = nil
                settingsStore.markListUpdateCompleted()
            }
            return manifest
        } catch let diagnostics as AdblockUpdateDiagnostics {
            lastFailedShardIdentifier = diagnostics.failedShardIdentifier
            lastUpdateDiagnostics = diagnostics
            throw diagnostics
        }
    }

    func contentRuleListDefinitions(
        for allowedKinds: Set<AdblockCompiledRuleGroupKind>
    ) throws -> [SumiContentRuleListDefinition] {
        guard let manifest = activeManifest else { return [] }
        let loader = AdblockManifestRuleListProvider.diskBackedDefinitionLoader(
            storageRoot: manifestStore.storageRoot
        )
        return try manifest.allNativeShards
            .filter { allowedKinds.contains($0.kind) }
            .sorted {
                if $0.kind == $1.kind {
                    return $0.id < $1.id
                }
                return $0.kind.rawValue < $1.kind.rawValue
            }
            .map(loader)
    }

    func requestAppResourceBundleInstall(
        profileId: String
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard await isAdblockEnabled() else { return nil }
        guard let bundleURL = SumiAdblockNativeRuleBundle.bundledDirectoryURL(for: profileId) else {
            let diagnostics = AdblockUpdateDiagnostics(
                summary: "No embedded Adblock bundle found for profile \(profileId).",
                generationSource: .embeddedBundle,
                bundleProfileId: profileId
            )
            lastFailedShardIdentifier = "embedded-bundle-\(profileId)"
            lastUpdateDiagnostics = diagnostics
            throw diagnostics
        }
        let previousManifest = try await manifestStore.activeManifest()
        return try await installEmbeddedBundle(
            at: bundleURL,
            source: .appResource,
            requestedProfileId: profileId,
            previousManifest: previousManifest,
            skipIfAlreadyInstalled: true
        )
    }

    func loadActiveManifestIfEnabled() async {
        guard await isAdblockEnabled() else { return }
        do {
            let manifest = try await manifestStore.activeManifest()
            do {
                if try await installEmbeddedBundleIfNeeded(previousManifest: manifest) != nil {
                    return
                }
            } catch where manifest != nil {
                try await manifestStore.validateCompiledShardFiles(for: manifest!)
                ruleListProvider.updateManifest(manifest)
                lastFailedShardIdentifier = nil
                if lastUpdateDiagnostics == nil {
                    lastUpdateDiagnostics = AdblockUpdateDiagnostics(
                        summary: "Embedded Adblock bundle install failed; retained active generation",
                        generationSource: manifest?.generationSource
                    )
                }
                return
            }
            if let manifest {
                try await manifestStore.validateCompiledShardFiles(for: manifest)
            }
            ruleListProvider.updateManifest(manifest)
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
#if DEBUG
                _ = try await self.updateCoordinator.updateIfEnabled(reason: "initial")
                let diagnostics = await self.updateCoordinator.latestDiagnosticsSnapshot()
                await MainActor.run {
                    self.lastFailedShardIdentifier = nil
                    self.lastUpdateDiagnostics = diagnostics
                }
#else
                await MainActor.run {
                    self.lastFailedShardIdentifier = nil
                    self.lastUpdateDiagnostics = AdblockUpdateDiagnostics(
                        summary: "No embedded Adblock bundle is available; runtime Adblock conversion is disabled outside DEBUG.",
                        generationSource: nil
                    )
                }
#endif
            } catch let diagnostics as AdblockUpdateDiagnostics {
                await MainActor.run {
                    self.lastFailedShardIdentifier = diagnostics.failedShardIdentifier
                    self.lastUpdateDiagnostics = diagnostics
                }
            } catch {
                await MainActor.run {
                    self.lastFailedShardIdentifier = "embedded-bundle"
                    self.lastUpdateDiagnostics = AdblockUpdateDiagnostics(
                        summary: "Embedded Adblock bundle install failed: \(error.localizedDescription)",
                        generationSource: .embeddedBundle
                    )
                }
            }
        }
    }

    private func installEmbeddedBundleIfNeeded(
        previousManifest: AdblockCompiledGenerationManifest?
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard let bundleURL = embeddedBundleURLProvider() else { return nil }
        return try await installEmbeddedBundle(
            at: bundleURL,
            previousManifest: previousManifest,
            skipIfAlreadyInstalled: true
        )
    }

#if DEBUG
    func requestEmbeddedBundleInstall(
        bundleURL: URL,
        source: SumiAdblockBundleInstallSource = .appResource,
        profileId: String? = nil
    ) async throws -> AdblockCompiledGenerationManifest? {
        guard await isAdblockEnabled() else { return nil }
        let previousManifest = try await manifestStore.activeManifest()
        return try await installEmbeddedBundle(
            at: bundleURL,
            source: source,
            requestedProfileId: profileId,
            previousManifest: previousManifest,
            skipIfAlreadyInstalled: false
        )
    }
#endif

    private func installEmbeddedBundle(
        at bundleURL: URL,
        source: SumiAdblockBundleInstallSource = .appResource,
        requestedProfileId: String? = nil,
        previousManifest: AdblockCompiledGenerationManifest?,
        skipIfAlreadyInstalled: Bool
    ) async throws -> AdblockCompiledGenerationManifest? {
        let generationSource = source.generationSource
        let bundle: SumiAdblockNativeRuleBundle
        do {
            bundle = try SumiAdblockNativeRuleBundle.load(directoryURL: bundleURL)
        } catch {
            let diagnostics = Self.embeddedBundleInstallDiagnostics(
                summary: "Adblock bundle install failed before publish: \(error.localizedDescription)",
                stage: Self.bundleLoadFailureStage(error),
                source: source,
                profileId: requestedProfileId,
                bundleURL: bundleURL,
                error: error
            )
            lastFailedShardIdentifier = diagnostics.failedShardIdentifier
            lastUpdateDiagnostics = diagnostics
            throw diagnostics
        }
        if skipIfAlreadyInstalled,
           previousManifest?.generationSource == generationSource,
           previousManifest?.nativeRuleBundleId == bundle.manifest.bundleId {
            return nil
        }

        let manifest = bundle.compiledGenerationManifest(
            previousManifest: previousManifest,
            installedDate: Date(),
            generationSource: generationSource
        )
        let definitions: [SumiContentRuleListDefinition]
        do {
            definitions = try bundle.contentRuleListDefinitions()
        } catch {
            let diagnostics = Self.embeddedBundleInstallDiagnostics(
                summary: "Adblock bundle verification failed: \(error.localizedDescription)",
                stage: Self.bundleLoadFailureStage(error),
                source: source,
                profileId: bundle.manifest.profileId,
                bundleURL: bundleURL,
                nativeRuleBundleId: bundle.manifest.bundleId,
                error: error
            )
            lastFailedShardIdentifier = diagnostics.failedShardIdentifier
            lastUpdateDiagnostics = diagnostics
            throw diagnostics
        }
        let preparedPublication: PreparedAdblockRuleListPublication
        do {
            preparedPublication = try await updateCoordinator.prepareEmbeddedBundlePublication(
                manifest: manifest,
                definitions: definitions
            )
        } catch let error as SumiContentBlockingCompilationError {
            let diagnostics = AdblockUpdateDiagnostics(
                summary: "Adblock bundle WebKit publish failed: \(error.localizedDescription)",
                stage: Self.contentBlockingFailureStage(error),
                failedShardIdentifier: error.identifier,
                generationSource: generationSource,
                bundleProfileId: bundle.manifest.profileId,
                bundlePath: bundleURL.path,
                nativeRuleBundleId: bundle.manifest.bundleId
            )
            lastFailedShardIdentifier = diagnostics.failedShardIdentifier
            lastUpdateDiagnostics = diagnostics
            throw diagnostics
        }

        let stagedShardURLs: [String: URL]
        do {
            stagedShardURLs = try bundle.stagedShardURLs()
        } catch {
            let diagnostics = Self.embeddedBundleInstallDiagnostics(
                summary: "Adblock bundle shard staging failed: \(error.localizedDescription)",
                stage: Self.bundleLoadFailureStage(error),
                source: source,
                profileId: bundle.manifest.profileId,
                bundleURL: bundleURL,
                nativeRuleBundleId: bundle.manifest.bundleId,
                error: error
            )
            lastFailedShardIdentifier = diagnostics.failedShardIdentifier
            lastUpdateDiagnostics = diagnostics
            throw diagnostics
        }
        let metadata = try await manifestStore.loadHTTPMetadata()
        do {
            try await manifestStore.commit(
                manifest: manifest,
                httpMetadata: metadata,
                stagedRawListURLs: [:],
                stagedCompiledShardURLs: stagedShardURLs
            )
        } catch {
            let diagnostics = AdblockUpdateDiagnostics(
                summary: "Adblock bundle manifest commit failed: \(error.localizedDescription)",
                stage: .embeddedBundleManifestCommit,
                generationSource: generationSource,
                bundleProfileId: bundle.manifest.profileId,
                bundlePath: bundleURL.path,
                nativeRuleBundleId: bundle.manifest.bundleId
            )
            lastFailedShardIdentifier = diagnostics.failedShardIdentifier
            lastUpdateDiagnostics = diagnostics
            throw diagnostics
        }

        await updateCoordinator.commitEmbeddedBundlePublication(preparedPublication)
        lastFailedShardIdentifier = nil
        lastUpdateDiagnostics = AdblockUpdateDiagnostics(
            summary: "success: Adblock bundle installed",
            generationSource: generationSource,
            bundleProfileId: bundle.manifest.profileId,
            bundlePath: bundleURL.path,
            nativeRuleBundleId: bundle.manifest.bundleId
        )
        return manifest
    }

    private static func embeddedBundleInstallDiagnostics(
        summary: String,
        stage: AdblockUpdateFailureStage,
        source: SumiAdblockBundleInstallSource,
        profileId: String?,
        bundleURL: URL,
        nativeRuleBundleId: String? = nil,
        error: Error
    ) -> AdblockUpdateDiagnostics {
        AdblockUpdateDiagnostics(
            summary: "\(summary); bundleSource=\(source.rawValue); bundleProfileId=\(profileId ?? "nil"); bundlePath=\(bundleURL.path); details=\(error.localizedDescription)",
            stage: stage,
            generationSource: source.generationSource,
            bundleProfileId: profileId,
            bundlePath: bundleURL.path,
            nativeRuleBundleId: nativeRuleBundleId
        )
    }

    private static func bundleLoadFailureStage(_ error: Error) -> AdblockUpdateFailureStage {
        guard let error = error as? SumiAdblockNativeRuleBundleError else {
            return .embeddedBundleManifestRead
        }
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

    private static func contentBlockingFailureStage(
        _ error: SumiContentBlockingCompilationError
    ) -> AdblockUpdateFailureStage {
        switch error {
        case .failedToCompileRuleList:
            return .embeddedBundleWebKitCompile
        case .missingCompiledRuleList:
            return .embeddedBundleLookup
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
    func cachedIdentifiersToForget(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        let activeIdentifiers = Set(activeRules.map(\.identifier.stringValue))
        return previousRules
            .map(\.identifier.stringValue)
            .filter { !activeIdentifiers.contains($0) }
    }

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
    private var preferredBundleInstallProfileIdsInFlight = Set<String>()

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
        guard surfaceEligibility(for: url).isEligible else {
            return SumiAdBlockingNormalTabDecision(
                status: status,
                effectivePolicy: policy,
                assets: .empty,
                contentBlockingService: nil
            )
        }
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

    func activeManifestIfLoaded() -> AdblockCompiledGenerationManifest? {
        cachedRuleListStore?.activeManifest
    }

    func contentRuleListDefinitions(
        for allowedKinds: Set<AdblockCompiledRuleGroupKind>
    ) throws -> [SumiContentRuleListDefinition] {
        try ruleListStoreIfEnabled().contentRuleListDefinitions(for: allowedKinds)
    }

    func ensurePreferredNativeRuleBundleInstalled(profileId: String) {
        guard isEnabled else { return }
        let store = ruleListStoreIfEnabled()
        guard store.activeManifest?.bundleProfileId != profileId else { return }
        guard store.activeManifest?.nativeRuleBundleId?.contains(".\(profileId).") != true else { return }
        guard preferredBundleInstallProfileIdsInFlight.insert(profileId).inserted else { return }

        Task { @MainActor [weak self, weak store] in
            defer { self?.preferredBundleInstallProfileIdsInFlight.remove(profileId) }
            await store?.loadActiveManifestIfEnabled()
            guard store?.activeManifest?.bundleProfileId != profileId else { return }
            guard store?.activeManifest?.nativeRuleBundleId?.contains(".\(profileId).") != true else { return }
            do {
                _ = try await store?.requestAppResourceBundleInstall(profileId: profileId)
            } catch {
                RuntimeDiagnostics.debug(
                    "Preferred Adblock bundle install failed for \(profileId): \(error.localizedDescription)",
                    category: "Adblock"
                )
            }
        }
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
        let eligibility = surfaceEligibility(for: url)
        let policy = effectivePolicy(for: url)
        let siteOverride = sitePolicyStoreIfEnabled().override(for: url)
        guard isEnabled else {
            let settings = cachedSettingsStore ?? settingsFactory()
            let validation = AdblockFilterListRegistry().validatedSelection(
                settings.selectedLists,
                profileKind: settings.selectedNativeProfile
            )
            return SumiAdblockAttachmentDiagnostics(
                siteHost: policy.host,
                globalAdblockEnabled: isEnabled,
                sitePolicyAllowsAdblock: policy.isEnabled,
                siteOverride: siteOverride,
                isEnabled: policy.isEnabled,
                hasActiveGeneration: false,
                attachedNativeGroups: [],
                attachedShardIdentifiers: [],
                expectedNetworkShardIdentifiers: [],
                expectedNativeCSSShardIdentifiers: [],
                missingShardIdentifiers: [],
                contentRuleListIdentifiers: [],
                selectedListIdentifiers: validation.resolvedIdentifiers,
                activeManifestListIdentifiers: [],
                compilerDiagnosticsSummary: nil,
                selectedNativeProfile: settings.selectedNativeProfile,
                activeCompiledNativeProfile: nil,
                selectedProfileDiffersFromActiveGeneration: true,
                activeGenerationId: nil,
                previousGenerationId: nil,
                previousGenerationRetained: false,
                lastSuccessfulUpdateDate: nil,
                nativeCompiler: nil,
                nativeCompilationSummary: nil,
                nativeSourceLists: [],
                generationSource: nil,
                nativeRuleBundleId: nil,
                bundleProfileId: nil,
                networkShardCount: 0,
                nativeCSSShardCount: 0,
                totalNetworkRuleCount: 0,
                totalNativeCSSRuleCount: 0,
                largestShardJSONByteCount: 0,
                failedShardIdentifier: nil,
                cosmeticMode: settings.cosmeticMode,
                enhancedRuntimeIsEnabled: false,
                trackingProtectionModuleEnabled: moduleRegistry.isEnabled(.trackingProtection),
                generationIsStale: settings.listSelectionRequiresUpdate,
                lastUpdateSummary: nil,
                lastUpdateError: nil,
                lastUpdateFailureStage: nil,
                lastUpdateListStatuses: [],
                effectiveSelectionDiagnostics: AdblockFilterListRegistry().effectiveSelectionDiagnostics(
                    selection: settings.selectedLists,
                    profileKind: settings.selectedNativeProfile
                ),
                latestRebuildMemoryDiagnostics: nil,
                currentProcessResidentMemoryBytes: Self.currentProcessResidentMemoryBytes(),
                unsafeNativeCSSFilteredRuleCount: 0,
                ineligibleSurfaceReason: eligibility.ineligibleReason
            )
        }

        let settings = settingsIfEnabled()
        let ruleListStore = ruleListStoreIfEnabled()
        let manifest = ruleListStore.activeManifest
        let canAttachToSurface = eligibility.isEligible && policy.isEnabled
        let allowedGroups = AdblockManifestRuleListProvider.attachedGroupKinds(
            for: settings?.cosmeticMode ?? .nativeCSS
        )
        let attachableShards = manifest?.allNativeShards
            .filter { allowedGroups.contains($0.kind) }
            ?? []
        let attachedShards = canAttachToSurface ? attachableShards : []
        let attachedGroups = Array(Set(attachedShards.map(\.kind)))
            .sorted { $0.rawValue < $1.rawValue }
        let attachedShardIdentifiers = attachedShards
            .map(\.webKitIdentifier)
            .sorted()
        let allShards = manifest?.allNativeShards ?? []
        let networkShards = manifest?.networkShards ?? []
        let nativeCSSShards = manifest?.nativeCSSShards ?? []
        let expectedNetworkShardIdentifiers = canAttachToSurface
            ? networkShards.map(\.webKitIdentifier).sorted()
            : []
        let expectedNativeCSSShardIdentifiers = canAttachToSurface && allowedGroups.contains(.nativeCosmeticCSS)
            ? nativeCSSShards.map(\.webKitIdentifier).sorted()
            : []
        let expectedShardIdentifiers = (expectedNetworkShardIdentifiers + expectedNativeCSSShardIdentifiers).sorted()
        let missingShardIdentifiers = expectedShardIdentifiers
            .filter { !attachedShardIdentifiers.contains($0) }
        let validation = AdblockFilterListRegistry().validatedSelection(
            settings?.selectedLists ?? .defaultSelection,
            profileKind: settings?.selectedNativeProfile ?? .currentDefault
        )
        let selectedProfile = settings?.selectedNativeProfile
        let activeProfile = manifest?.nativeProfile
        let lastDiagnostics = ruleListStore.lastUpdateDiagnostics
        let lastSummary = lastDiagnostics?.summary
        let lastError = lastDiagnostics?.stage == nil
            ? ruleListStore.lastFailedShardIdentifier.map { "Failed shard: \($0)" }
            : lastDiagnostics?.summary
        let compilerDiagnosticsSummary = manifest?.compilerDiagnosticsSummary

        return SumiAdblockAttachmentDiagnostics(
            siteHost: policy.host,
            globalAdblockEnabled: true,
            sitePolicyAllowsAdblock: policy.isEnabled,
            siteOverride: siteOverride,
            isEnabled: policy.isEnabled,
            hasActiveGeneration: manifest != nil,
            attachedNativeGroups: attachedGroups,
            attachedShardIdentifiers: attachedShardIdentifiers,
            expectedNetworkShardIdentifiers: expectedNetworkShardIdentifiers,
            expectedNativeCSSShardIdentifiers: expectedNativeCSSShardIdentifiers,
            missingShardIdentifiers: missingShardIdentifiers,
            contentRuleListIdentifiers: canAttachToSurface && attachedShardIdentifiers.isEmpty
                ? contentRuleListIdentifiers()
                : attachedShardIdentifiers,
            selectedListIdentifiers: validation.resolvedIdentifiers,
            activeManifestListIdentifiers: manifest?.selectedFilterLists.map(\.id).sorted() ?? [],
            compilerDiagnosticsSummary: compilerDiagnosticsSummary,
            selectedNativeProfile: selectedProfile,
            activeCompiledNativeProfile: activeProfile,
            selectedProfileDiffersFromActiveGeneration: selectedProfile != activeProfile,
            activeGenerationId: manifest?.activeGenerationId,
            previousGenerationId: manifest?.previousGenerationId,
            previousGenerationRetained: manifest?.previousGenerationId != nil,
            lastSuccessfulUpdateDate: manifest?.lastSuccessfulUpdateDate,
            nativeCompiler: manifest?.nativeCompiler,
            nativeCompilationSummary: manifest?.nativeCompilationSummary,
            nativeSourceLists: manifest?.nativeCompilerSourceLists ?? [],
            generationSource: manifest?.generationSource,
            nativeRuleBundleId: manifest?.nativeRuleBundleId,
            bundleProfileId: manifest?.bundleProfileId ?? manifest?.nativeProfile?.rawValue,
            networkShardCount: networkShards.count,
            nativeCSSShardCount: nativeCSSShards.count,
            totalNetworkRuleCount: networkShards.reduce(0) { $0 + $1.approximateRuleCount },
            totalNativeCSSRuleCount: nativeCSSShards.reduce(0) { $0 + $1.approximateRuleCount },
            largestShardJSONByteCount: allShards.map(\.jsonByteCount).max() ?? 0,
            failedShardIdentifier: ruleListStore.lastFailedShardIdentifier,
            cosmeticMode: settings?.cosmeticMode,
            enhancedRuntimeIsEnabled: settings?.cosmeticMode == .enhancedRuntime,
            trackingProtectionModuleEnabled: moduleRegistry.isEnabled(.trackingProtection),
            generationIsStale: Self.generationIsStale(
                manifest: manifest,
                settings: settings,
                configuredNativeCompilerIdentity: ruleListStore.configuredNativeCompilerIdentity
            ),
            lastUpdateSummary: lastSummary,
            lastUpdateError: lastError,
            lastUpdateFailureStage: lastDiagnostics?.stage,
            lastUpdateListStatuses: lastDiagnostics?.listStatuses ?? [],
            effectiveSelectionDiagnostics: lastDiagnostics?.selectionDiagnostics
                ?? AdblockFilterListRegistry().effectiveSelectionDiagnostics(
                    selection: settings?.selectedLists ?? .defaultSelection,
                    profileKind: settings?.selectedNativeProfile ?? .currentDefault
                ),
            latestRebuildMemoryDiagnostics: lastDiagnostics?.memoryDiagnostics,
            currentProcessResidentMemoryBytes: Self.currentProcessResidentMemoryBytes(),
            unsafeNativeCSSFilteredRuleCount: Self.diagnosticsIntegerValue(
                named: "unsafeNativeCSSRootSelectorsFiltered",
                in: compilerDiagnosticsSummary
            ) ?? 0,
            ineligibleSurfaceReason: eligibility.ineligibleReason
        )
    }

    func attachmentDiagnosticsReport(for url: URL?) -> String {
        attachmentDiagnostics(for: url).developerReport
    }

    func currentTabDiagnostics(
        for url: URL?,
        appliedState: SumiAdblockAttachmentState?,
        reloadRequired: Bool,
        actualAttachedRuleListIdentifiers: [String]? = nil
    ) -> SumiAdblockCurrentTabDiagnostics {
        let diagnostics = attachmentDiagnostics(for: url)
        let recordedApplied = appliedState?.attachedShardIdentifiers ?? []
        let attached = (actualAttachedRuleListIdentifiers ?? recordedApplied)
            .filter(Self.isAdblockGeneratedRuleListIdentifier)
            .sorted()
        let attachedSet = Set(attached)
        let attachedNetwork = diagnostics.expectedNetworkShardIdentifiers.filter(attachedSet.contains)
        let attachedNativeCSS = diagnostics.expectedNativeCSSShardIdentifiers.filter(attachedSet.contains)
        let expected = diagnostics.expectedNetworkShardIdentifiers + diagnostics.expectedNativeCSSShardIdentifiers
        let missing = expected.filter { !attachedSet.contains($0) }
        let expectedSet = Set(expected)
        let unexpectedOld = attached.filter { !expectedSet.contains($0) }
        let attachedGenerationIds = Set(attached.compactMap(Self.generationIdentifier(fromAdblockRuleListIdentifier:)))
            .sorted()
        let attachedGenerationId = attachedGenerationIds.count == 1 ? attachedGenerationIds[0] : nil
        let hasMixedGenerationAttachment = attachedGenerationIds.count > 1
        let attachedWhilePerSiteDisabled = !diagnostics.sitePolicyAllowsAdblock && !attached.isEmpty
        let nativeCSSAttachedWhileOff = diagnostics.cosmeticMode == .off
            && attached.contains { Self.isNativeCSSRuleListIdentifier($0) }
        let activeGenerationId = diagnostics.activeGenerationId
        let tabUsesActiveGeneration = activeGenerationId != nil
            && !attached.isEmpty
            && missing.isEmpty
            && unexpectedOld.isEmpty
        let tabAppearsOlder = activeGenerationId != nil
            && !attached.isEmpty
            && !tabUsesActiveGeneration
            && attachedGenerationIds.allSatisfy { $0 != activeGenerationId }
        let reloadRequiredForActiveGeneration = reloadRequired
            || attachedWhilePerSiteDisabled
            || nativeCSSAttachedWhileOff
            || hasMixedGenerationAttachment
            || !missing.isEmpty
            || !unexpectedOld.isEmpty
        let assessment = diagnostics.ineligibleSurfaceReason != nil
            ? "ineligible surface, no Adblock attachment expected"
            : Self.attachmentAssessment(
                hasActiveGeneration: diagnostics.hasActiveGeneration,
                attached: attached,
                missing: missing,
                unexpectedOld: unexpectedOld,
                attachedWhilePerSiteDisabled: attachedWhilePerSiteDisabled,
                nativeCSSAttachedWhileOff: nativeCSSAttachedWhileOff,
                hasMixedGenerationAttachment: hasMixedGenerationAttachment,
                tabUsesActiveGeneration: tabUsesActiveGeneration,
                tabAppearsOlder: tabAppearsOlder,
                reloadRequired: reloadRequired
            )
        let suspectedBlankPageCategory = Self.suspectedBlankPageCategory(
            ineligibleSurfaceReason: diagnostics.ineligibleSurfaceReason,
            attachedNetwork: attachedNetwork,
            attachedNativeCSS: attachedNativeCSS,
            missing: missing,
            unexpectedOld: unexpectedOld,
            hasMixedGenerationAttachment: hasMixedGenerationAttachment,
            reloadRequiredForActiveGeneration: reloadRequiredForActiveGeneration,
            cosmeticMode: diagnostics.cosmeticMode,
            hasActiveGeneration: diagnostics.hasActiveGeneration,
            isEnabled: diagnostics.isEnabled
        )
        return SumiAdblockCurrentTabDiagnostics(
            urlString: url?.absoluteString,
            host: url?.host,
            normalizedSiteKey: diagnostics.siteHost,
            globalAdblockEnabled: diagnostics.globalAdblockEnabled,
            perSiteAdblockEnabled: diagnostics.sitePolicyAllowsAdblock,
            reloadRequired: reloadRequired,
            activeGenerationId: diagnostics.activeGenerationId,
            selectedNativeProfile: diagnostics.selectedNativeProfile,
            activeCompiledNativeProfile: diagnostics.activeCompiledNativeProfile,
            cosmeticMode: diagnostics.cosmeticMode,
            expectedNetworkShardIdentifiers: diagnostics.expectedNetworkShardIdentifiers,
            expectedNativeCSSShardIdentifiers: diagnostics.expectedNativeCSSShardIdentifiers,
            recordedAppliedShardIdentifiers: recordedApplied,
            actualAttachedShardIdentifiers: attached,
            attachedNetworkShardIdentifiers: attachedNetwork,
            attachedNativeCSSShardIdentifiers: attachedNativeCSS,
            missingShardIdentifiers: missing,
            unexpectedOldShardIdentifiers: unexpectedOld,
            attachedGenerationIds: attachedGenerationIds,
            attachedGenerationId: attachedGenerationId,
            tabUsesActiveGeneration: tabUsesActiveGeneration,
            tabAppearsToUseOlderGeneration: tabAppearsOlder,
            hasMixedGenerationAttachment: hasMixedGenerationAttachment,
            attachedWhilePerSiteAdblockDisabled: attachedWhilePerSiteDisabled,
            nativeCSSAttachedWhileCosmeticModeOff: nativeCSSAttachedWhileOff,
            reloadRequiredForActiveGeneration: reloadRequiredForActiveGeneration,
            attachmentAssessment: assessment,
            suspectedBlankPageCategory: suspectedBlankPageCategory,
            attachmentMemorySnapshot: Self.attachmentMemorySnapshot(),
            ineligibleSurfaceReason: diagnostics.ineligibleSurfaceReason
        )
    }

    #if DEBUG
    func copyDiagnosticsReport(
        for url: URL?,
        currentTabDiagnostics: SumiAdblockCurrentTabDiagnostics?,
        targetDescription: String = "current tab",
        requestingURL: URL? = nil
    ) -> String {
        let diagnostics = attachmentDiagnostics(for: url)
        let targetURLString = url?.absoluteString ?? "nil"
        var lines = [
            "Sumi Adblock Copy Diagnostics",
            "timestamp=\(Self.iso8601Timestamp(Date()))",
            "targetSource=\(targetDescription)",
            "targetURL=\(targetURLString)",
            "diagnosticsTargetURL=\(targetURLString)",
            "requestingURL=\(requestingURL?.absoluteString ?? "nil")",
            "currentURL=\(targetURLString)",
            "webViewSurfaceEligible=\(diagnostics.ineligibleSurfaceReason == nil)",
            diagnostics.developerReport,
        ]
        if let currentTabDiagnostics {
            lines.append(currentTabDiagnostics.developerReport)
        } else {
            lines.append("Sumi Adblock current-tab diagnostics\ncurrentTab=nil")
        }
        lines.append(
            "blankPageComparisonHint=\(Self.blankPageComparisonHint(cosmeticMode: diagnostics.cosmeticMode, currentTabDiagnostics: currentTabDiagnostics))"
        )
        return lines.joined(separator: "\n")
    }
    #endif

    #if DEBUG
    func rebuildSelectedAdblockProfileNow() async throws -> AdblockCompiledGenerationManifest? {
        guard isEnabled else {
            throw AdblockUpdateDiagnostics(
                summary: "Enable built-in Adblock before rebuilding the selected native profile."
            )
        }
        let store = ruleListStoreIfEnabled()
        let manifest = try await store.requestManualUpdate()
        cachedSettingsStore?.markListUpdateCompleted()
        return manifest
    }

    func embeddedAdblockBundleSnapshot() -> SumiEmbeddedAdblockBundleSnapshot {
        SumiEmbeddedAdblockBundleCatalog.snapshot()
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
            bundleURL = SumiEmbeddedAdblockBundleCatalog.developmentBundleURL(for: profileId)
        case .futureRemoteBundle:
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

    private static func isAdblockGeneratedRuleListIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("sumi.adblock.")
    }

    private static func isNativeCSSRuleListIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("sumi.adblock.nativeCSS.")
    }

    private static func generationIdentifier(fromAdblockRuleListIdentifier identifier: String) -> String? {
        guard isAdblockGeneratedRuleListIdentifier(identifier) else { return nil }
        let components = identifier.split(separator: ".").map(String.init)
        guard components.count >= 4 else { return nil }
        return components[3]
    }

    private static func attachmentAssessment(
        hasActiveGeneration: Bool,
        attached: [String],
        missing: [String],
        unexpectedOld: [String],
        attachedWhilePerSiteDisabled: Bool,
        nativeCSSAttachedWhileOff: Bool,
        hasMixedGenerationAttachment: Bool,
        tabUsesActiveGeneration: Bool,
        tabAppearsOlder: Bool,
        reloadRequired: Bool
    ) -> String {
        if attachedWhilePerSiteDisabled {
            return "attached while per-site Adblock is disabled"
        }
        if nativeCSSAttachedWhileOff {
            return "native CSS attached while cosmetic mode is off"
        }
        if hasMixedGenerationAttachment {
            return "mixed old and active Adblock generations attached"
        }
        if !unexpectedOld.isEmpty {
            return "unexpected old Adblock shards attached"
        }
        if !missing.isEmpty {
            return "expected Adblock shards missing"
        }
        if tabUsesActiveGeneration {
            return reloadRequired ? "active generation attached but reload is still required" : "active generation attached"
        }
        if tabAppearsOlder {
            return "current tab appears to use an older generation"
        }
        if !hasActiveGeneration {
            return "no active Adblock generation"
        }
        if attached.isEmpty {
            return "no Adblock shards attached"
        }
        return "inconclusive"
    }

    private static func suspectedBlankPageCategory(
        ineligibleSurfaceReason: String?,
        attachedNetwork: [String],
        attachedNativeCSS: [String],
        missing: [String],
        unexpectedOld: [String],
        hasMixedGenerationAttachment: Bool,
        reloadRequiredForActiveGeneration: Bool,
        cosmeticMode: SumiAdblockCosmeticMode?,
        hasActiveGeneration: Bool,
        isEnabled: Bool
    ) -> String {
        if ineligibleSurfaceReason != nil {
            return "D internal/ineligible surface"
        }
        if reloadRequiredForActiveGeneration
            || hasMixedGenerationAttachment
            || !missing.isEmpty
            || !unexpectedOld.isEmpty {
            return "C mixed/stale/reload-required attachment"
        }
        guard isEnabled, hasActiveGeneration else {
            return "not diagnosable"
        }
        if cosmeticMode == .nativeCSS || cosmeticMode == .enhancedRuntime,
           !attachedNativeCSS.isEmpty {
            return "A possible native CSS over-hiding; compare cosmeticMode.off"
        }
        if cosmeticMode == .off,
           !attachedNetwork.isEmpty {
            return "B possible network overblocking; compare Adblock disabled"
        }
        return "not diagnosable"
    }

    private static func generationIsStale(
        manifest: AdblockCompiledGenerationManifest?,
        settings: AdblockSettingsStore?,
        configuredNativeCompilerIdentity: NativeContentBlockingCompilerIdentity
    ) -> Bool {
        guard let manifest else {
            return settings?.listSelectionRequiresUpdate ?? false
        }
        guard manifest.generationSource == .runtimeGenerated else {
            return false
        }
        return (settings?.listSelectionRequiresUpdate ?? false)
            || manifest.nativeProfile != settings?.selectedNativeProfile
            || manifest.nativeCompiler != configuredNativeCompilerIdentity
    }

    private static func diagnosticsIntegerValue(named key: String, in summary: String?) -> Int? {
        guard let summary else { return nil }
        let prefix = "\(key)="
        return summary
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix(prefix) }
            .flatMap { Int($0.dropFirst(prefix.count)) }
    }

    private static func currentProcessResidentMemoryBytes() -> UInt64? {
#if DEBUG
        return AdblockProcessMemorySampler.residentMemoryBytes()
#else
        return nil
#endif
    }

    private static func attachmentMemorySnapshot() -> AdblockRebuildMemorySnapshot? {
#if DEBUG
        guard let residentMemoryBytes = AdblockProcessMemorySampler.residentMemoryBytes() else {
            return nil
        }
        return AdblockRebuildMemorySnapshot(
            stage: .afterPageReloadAttachment,
            timestamp: Date(),
            residentMemoryBytes: residentMemoryBytes
        )
#else
        return nil
#endif
    }

    private static func blankPageComparisonHint(
        cosmeticMode: SumiAdblockCosmeticMode?,
        currentTabDiagnostics: SumiAdblockCurrentTabDiagnostics?
    ) -> String {
        guard let currentTabDiagnostics else {
            return "no current tab diagnostics"
        }
        if cosmeticMode == .nativeCSS || cosmeticMode == .enhancedRuntime {
            if !currentTabDiagnostics.attachedNativeCSSShardIdentifiers.isEmpty {
                return "Compare cosmeticMode.off against nativeCSS. If off renders and nativeCSS blanks, suspected native CSS over-hide."
            }
        }
        if !currentTabDiagnostics.attachedNetworkShardIdentifiers.isEmpty
            || currentTabDiagnostics.cosmeticMode == .off {
            return "Compare Adblock off against cosmeticMode.off. If off mode blanks while Adblock off renders, suspected network overblocking."
        }
        return "insufficient attached shard state"
    }

    private static func iso8601Timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
