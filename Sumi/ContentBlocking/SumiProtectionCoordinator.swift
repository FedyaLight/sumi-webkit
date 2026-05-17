import Combine
import CryptoKit
import Foundation

enum SumiProtectionBundleProfile {
    static let adblock = "adguardAdsPrivacy"
    static let extreme = "maximumCustomReference"
}

enum SumiProtectionLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case protection
    case adblock
    case extreme

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .off:
            return "Off"
        case .protection:
            return "Protection"
        case .adblock:
            return "Adblock"
        case .extreme:
            return "Extreme"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "No blocking."
        case .protection:
            return "Lightweight tracker protection."
        case .adblock:
            return "Recommended native ad blocking with tracker protection."
        case .extreme:
            return "Strongest native mode. May use more memory or break sites."
        }
    }

    var requestedGroups: [SumiProtectionGroupKind] {
        switch self {
        case .off:
            return []
        case .protection:
            return [.trackingNetwork]
        case .adblock:
            return [.trackingNetwork, .adblockAdsPrivacyNetwork]
        case .extreme:
            return [.trackingNetwork, .maximumNativeNetwork, .maximumNativeCSS]
        }
    }

    var preferredBundleProfileId: String? {
        switch self {
        case .off, .protection:
            return nil
        case .adblock:
            return SumiProtectionBundleProfile.adblock
        case .extreme:
            return SumiProtectionBundleProfile.extreme
        }
    }

    var adblockRuleGroupKinds: Set<AdblockCompiledRuleGroupKind> {
        switch self {
        case .off, .protection:
            return []
        case .adblock:
            return [.network]
        case .extreme:
            return [.network, .nativeCosmeticCSS]
        }
    }
}

enum SumiProtectionGroupKind: String, Codable, CaseIterable, Hashable, Sendable {
    case trackingNetwork
    case adblockAdsPrivacyNetwork
    case maximumNativeNetwork
    case maximumNativeCSS
}

struct SumiProtectionAttachmentState: Equatable, Sendable {
    let siteHost: String?
    let requestedLevel: SumiProtectionLevel
    let effectiveLevel: SumiProtectionLevel
    let activeGroups: [SumiProtectionGroupKind]
    let attachedRuleListIdentifiers: [String]
    let activeGenerationId: String?

    var isEnabled: Bool {
        effectiveLevel != .off && !activeGroups.isEmpty
    }

    init(
        siteHost: String?,
        requestedLevel: SumiProtectionLevel,
        effectiveLevel: SumiProtectionLevel,
        activeGroups: [SumiProtectionGroupKind],
        attachedRuleListIdentifiers: [String] = [],
        activeGenerationId: String? = nil
    ) {
        self.siteHost = siteHost
        self.requestedLevel = requestedLevel
        self.effectiveLevel = effectiveLevel
        self.activeGroups = activeGroups.sorted { $0.rawValue < $1.rawValue }
        self.attachedRuleListIdentifiers = attachedRuleListIdentifiers.sorted()
        self.activeGenerationId = activeGenerationId
    }

    static func disabled(
        siteHost: String?,
        requestedLevel: SumiProtectionLevel = .off
    ) -> SumiProtectionAttachmentState {
        SumiProtectionAttachmentState(
            siteHost: siteHost,
            requestedLevel: requestedLevel,
            effectiveLevel: .off,
            activeGroups: []
        )
    }
}

struct SumiProtectionReloadRequirement: Equatable {
    let siteHost: String?
    let desiredAttachmentState: SumiProtectionAttachmentState
}

struct SumiProtectionDedupeSummary: Equatable, Sendable {
    let inputRuleListCount: Int
    let finalRuleListCount: Int
    let duplicateIdentifierCountRemoved: Int
    let duplicateCanonicalJSONCountRemoved: Int
    let duplicateGroupContentHashCountRemoved: Int
    let canonicalJSONUnavailableCount: Int
    let removedIdentifiers: [String]

    static let empty = SumiProtectionDedupeSummary(
        inputRuleListCount: 0,
        finalRuleListCount: 0,
        duplicateIdentifierCountRemoved: 0,
        duplicateCanonicalJSONCountRemoved: 0,
        duplicateGroupContentHashCountRemoved: 0,
        canonicalJSONUnavailableCount: 0,
        removedIdentifiers: []
    )

    var reportLine: String {
        "input=\(inputRuleListCount); final=\(finalRuleListCount); duplicateIdentifiersRemoved=\(duplicateIdentifierCountRemoved); duplicateCanonicalJSONRemoved=\(duplicateCanonicalJSONCountRemoved); duplicateGroupContentHashRemoved=\(duplicateGroupContentHashCountRemoved); canonicalJSONUnavailable=\(canonicalJSONUnavailableCount)"
    }
}

struct SumiProtectionOverlapSummary: Equatable, Sendable {
    let exactCanonicalOverlapCount: Int
    let domainResourceOverlapCount: Int
    let exactComparisonAvailable: Bool
    let notes: [String]

    static let empty = SumiProtectionOverlapSummary(
        exactCanonicalOverlapCount: 0,
        domainResourceOverlapCount: 0,
        exactComparisonAvailable: false,
        notes: []
    )

    static let deferred = SumiProtectionOverlapSummary(
        exactCanonicalOverlapCount: 0,
        domainResourceOverlapCount: 0,
        exactComparisonAvailable: false,
        notes: ["Detailed overlap diagnostics are available in Copy Diagnostics."]
    )

    var reportLine: String {
        "exactCanonicalOverlap=\(exactCanonicalOverlapCount); domainResourceOverlap=\(domainResourceOverlapCount); exactComparisonAvailable=\(exactComparisonAvailable); notes=\(notes.joined(separator: " | "))"
    }
}

struct SumiProtectionRulePlan: Equatable, Sendable {
    let requestedLevel: SumiProtectionLevel
    let effectiveLevel: SumiProtectionLevel
    let siteHost: String?
    let siteOverride: SumiAdblockSiteOverride
    let sitePolicyAllowsProtection: Bool
    let activeGroups: [SumiProtectionGroupKind]
    let inactiveGroups: [SumiProtectionGroupKind]
    let bundleSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let requiredBundleProfileId: String?
    let activeGenerationId: String?
    let previousGenerationId: String?
    let previousGenerationRetained: Bool
    let ruleCountsByGroup: [SumiProtectionGroupKind: Int]
    let shardCountsByGroup: [SumiProtectionGroupKind: Int]
    let expectedRuleListIdentifiers: [String]
    let dedupeSummary: SumiProtectionDedupeSummary
    let overlapSummary: SumiProtectionOverlapSummary
    let ineligibleSurfaceReason: String?
    let planningErrors: [String]
    let ruleDefinitions: [SumiContentRuleListDefinition]

    var attachmentState: SumiProtectionAttachmentState {
        SumiProtectionAttachmentState(
            siteHost: siteHost,
            requestedLevel: requestedLevel,
            effectiveLevel: effectiveLevel,
            activeGroups: activeGroups,
            attachedRuleListIdentifiers: expectedRuleListIdentifiers,
            activeGenerationId: activeGenerationId
        )
    }

    var trackingGroupActive: Bool {
        activeGroups.contains(.trackingNetwork)
    }

    var adblockGroupActive: Bool {
        activeGroups.contains(.adblockAdsPrivacyNetwork)
            || activeGroups.contains(.maximumNativeNetwork)
    }

    var nativeCSSGroupActive: Bool {
        activeGroups.contains(.maximumNativeCSS)
    }
}

struct SumiProtectionNormalTabDecision: Equatable, Sendable {
    let plan: SumiProtectionRulePlan
    let contentBlockingService: SumiContentBlockingService?

    var attachmentState: SumiProtectionAttachmentState {
        plan.attachmentState
    }

    var trackingAttachmentState: SumiTrackingProtectionAttachmentState {
        SumiTrackingProtectionAttachmentState(
            siteHost: plan.siteHost,
            isEnabled: plan.trackingGroupActive
        )
    }

    var adblockAttachmentState: SumiAdblockAttachmentState {
        SumiAdblockAttachmentState(
            siteHost: plan.siteHost,
            isEnabled: plan.adblockGroupActive || plan.nativeCSSGroupActive,
            hasEnhancedRuntime: false,
            attachedShardIdentifiers: plan.expectedRuleListIdentifiers.filter {
                $0.hasPrefix("sumi.adblock.")
            }
        )
    }

    static func == (lhs: SumiProtectionNormalTabDecision, rhs: SumiProtectionNormalTabDecision) -> Bool {
        lhs.plan == rhs.plan
            && (lhs.contentBlockingService == nil) == (rhs.contentBlockingService == nil)
    }
}

struct SumiProtectionCurrentTabDiagnostics: Equatable, Sendable {
    let urlString: String?
    let host: String?
    let normalizedSiteKey: String?
    let protectionLevel: SumiProtectionLevel
    let effectiveProtectionLevel: SumiProtectionLevel
    let activeGroups: [SumiProtectionGroupKind]
    let inactiveGroups: [SumiProtectionGroupKind]
    let desiredGroups: [SumiProtectionGroupKind]
    let perSiteProtectionEnabled: Bool
    let reloadRequired: Bool
    let generationSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let requiredBundleProfileId: String?
    let trackingGroupActive: Bool
    let adblockGroupActive: Bool
    let nativeCSSGroupActive: Bool
    let ruleCountsByGroup: [SumiProtectionGroupKind: Int]
    let shardCountsByGroup: [SumiProtectionGroupKind: Int]
    let dedupeSummary: SumiProtectionDedupeSummary
    let overlapSummary: SumiProtectionOverlapSummary
    let expectedRuleListIdentifiers: [String]
    let lookupSucceededIdentifiers: [String]
    let lookupFailedIdentifiers: [String]
    let addedToUserContentControllerIdentifiers: [String]
    let recordedAppliedRuleListIdentifiers: [String]
    let actualAttachedRuleListIdentifiers: [String]
    let missingRuleListIdentifiers: [String]
    let missingAfterAttachmentIdentifiers: [String]
    let unexpectedOldRuleListIdentifiers: [String]
    let activeGenerationId: String?
    let appliedProtectionGenerationId: String?
    let appliedProtectionGroups: [SumiProtectionGroupKind]
    let previousGenerationId: String?
    let previousGenerationRetained: Bool
    let ruleListIdentifierSamplesByGroup: [SumiProtectionGroupKind: [String]]
    let eligibleSurfaceReason: String?
    let ineligibleSurfaceReason: String?
    let currentProcessResidentMemoryBytes: UInt64?
    let planningErrors: [String]

    var developerReport: String {
        [
            "Sumi Adblock & Protection current-tab diagnostics",
            "url=\(urlString ?? "nil")",
            "host=\(host ?? "nil")",
            "normalizedSiteKey=\(normalizedSiteKey ?? "nil")",
            "protectionLevel=\(protectionLevel.rawValue)",
            "effectiveProtectionLevel=\(effectiveProtectionLevel.rawValue)",
            "activeGroups=\(activeGroups.map(\.rawValue).joined(separator: ","))",
            "inactiveGroups=\(inactiveGroups.map(\.rawValue).joined(separator: ","))",
            "desiredGroups=\(desiredGroups.map(\.rawValue).joined(separator: ","))",
            "perSiteProtectionEnabled=\(perSiteProtectionEnabled)",
            "reloadRequired=\(reloadRequired)",
            "generationSource=\(generationSource?.rawValue ?? "nil")",
            "nativeRuleBundleId=\(nativeRuleBundleId ?? "nil")",
            "bundleProfileId=\(bundleProfileId ?? "nil")",
            "requiredBundleProfileId=\(requiredBundleProfileId ?? "nil")",
            "trackingGroupActive=\(trackingGroupActive)",
            "adblockGroupActive=\(adblockGroupActive)",
            "nativeCSSGroupActive=\(nativeCSSGroupActive)",
            "ruleCountsByGroup=\(Self.renderCounts(ruleCountsByGroup))",
            "shardCountsByGroup=\(Self.renderCounts(shardCountsByGroup))",
            "dedupeSummary=\(dedupeSummary.reportLine)",
            "overlapSummary=\(overlapSummary.reportLine)",
            "expectedRuleListIdentifiers=\(expectedRuleListIdentifiers.joined(separator: ","))",
            "lookupSucceededIdentifiers=\(lookupSucceededIdentifiers.joined(separator: ","))",
            "lookupFailedIdentifiers=\(lookupFailedIdentifiers.joined(separator: ","))",
            "addedToUserContentControllerIdentifiers=\(addedToUserContentControllerIdentifiers.joined(separator: ","))",
            "recordedAppliedRuleListIdentifiers=\(recordedAppliedRuleListIdentifiers.joined(separator: ","))",
            "actualAttachedRuleListIdentifiers=\(actualAttachedRuleListIdentifiers.joined(separator: ","))",
            "missingRuleListIdentifiers=\(missingRuleListIdentifiers.joined(separator: ","))",
            "missingAfterAttachmentIdentifiers=\(missingAfterAttachmentIdentifiers.joined(separator: ","))",
            "unexpectedOldRuleListIdentifiers=\(unexpectedOldRuleListIdentifiers.joined(separator: ","))",
            "activeGenerationId=\(activeGenerationId ?? "nil")",
            "appliedProtectionGenerationId=\(appliedProtectionGenerationId ?? "nil")",
            "appliedProtectionGroups=\(appliedProtectionGroups.map(\.rawValue).joined(separator: ","))",
            "previousGenerationId=\(previousGenerationId ?? "nil")",
            "previousGenerationRetained=\(previousGenerationRetained)",
            "ruleListIdentifierSamplesByGroup=\(Self.renderIdentifierSamples(ruleListIdentifierSamplesByGroup))",
            "eligibleSurfaceReason=\(eligibleSurfaceReason ?? "nil")",
            "ineligibleSurfaceReason=\(ineligibleSurfaceReason ?? "nil")",
            "currentProcessResidentMemoryBytes=\(currentProcessResidentMemoryBytes.map(String.init) ?? "nil")",
            "planningErrors=\(planningErrors.joined(separator: " | "))",
        ].joined(separator: "\n")
    }

    static func renderCounts(_ counts: [SumiProtectionGroupKind: Int]) -> String {
        SumiProtectionGroupKind.allCases
            .compactMap { group in
                counts[group].map { "\(group.rawValue):\($0)" }
            }
            .joined(separator: ",")
    }

    static func renderIdentifierSamples(_ samples: [SumiProtectionGroupKind: [String]]) -> String {
        SumiProtectionGroupKind.allCases
            .compactMap { group in
                samples[group].map { "\(group.rawValue):\($0.joined(separator: "|"))" }
            }
            .joined(separator: ",")
    }
}

struct SumiProtectionGlobalDiagnostics: Equatable, Sendable {
    let selectedProtectionLevel: SumiProtectionLevel
    let appliedProtectionLevel: SumiProtectionLevel
    let generationSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let activeGenerationId: String?
    let requiredBundleProfileId: String?
    let preparedBundleAvailable: Bool
    let preparedBundleSource: SumiAdblockBundleInstallSource?
    let searchedBundlePaths: [SumiPreparedAdblockBundleSearchPath]
    let applyNeeded: Bool
    let lastApplySummary: String?
    let lastApplyError: String?
    let globalGroupsAvailable: [SumiProtectionGroupKind]
    let trackingSourceAvailable: Bool
    let adblockBundleAvailable: Bool
}

struct SumiProtectionApplyOutcome: Equatable, Sendable {
    let selectedLevel: SumiProtectionLevel
    let previousAppliedLevel: SumiProtectionLevel
    let appliedLevel: SumiProtectionLevel
    let installedBundleProfileId: String?
    let summary: String
}

@MainActor
final class SumiProtectionSettings: ObservableObject {
    static let shared = SumiProtectionSettings()

    private enum DefaultsKey {
        static let level = "settings.protection.level"
        static let appliedLevel = "settings.protection.appliedLevel"
        static let legacyAdblockEnabled = "settings.modules.adBlocking.enabled"
        static let legacyTrackingEnabled = "settings.modules.trackingProtection.enabled"
        static let legacyTrackingGlobalMode = "settings.trackingProtection.globalMode"
    }

    @Published private(set) var level: SumiProtectionLevel {
        didSet {
            userDefaults.set(level.rawValue, forKey: DefaultsKey.level)
            changesSubject.send(())
        }
    }

    @Published private(set) var appliedLevel: SumiProtectionLevel {
        didSet {
            userDefaults.set(appliedLevel.rawValue, forKey: DefaultsKey.appliedLevel)
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
        let resolvedLevel: SumiProtectionLevel
        if let rawLevel = userDefaults.string(forKey: DefaultsKey.level),
           let decodedLevel = SumiProtectionLevel(rawValue: rawLevel) {
            resolvedLevel = decodedLevel
        } else {
            resolvedLevel = Self.migratedLevel(from: userDefaults)
            userDefaults.set(resolvedLevel.rawValue, forKey: DefaultsKey.level)
        }
        level = resolvedLevel

        if let rawAppliedLevel = userDefaults.string(forKey: DefaultsKey.appliedLevel),
           let decodedAppliedLevel = SumiProtectionLevel(rawValue: rawAppliedLevel) {
            appliedLevel = decodedAppliedLevel
        } else {
            appliedLevel = resolvedLevel
            userDefaults.set(resolvedLevel.rawValue, forKey: DefaultsKey.appliedLevel)
        }
    }

    func setLevel(_ level: SumiProtectionLevel) {
        guard self.level != level else { return }
        self.level = level
    }

    func setAppliedLevel(_ level: SumiProtectionLevel) {
        guard appliedLevel != level else { return }
        appliedLevel = level
    }

    private static func migratedLevel(from userDefaults: UserDefaults) -> SumiProtectionLevel {
        if userDefaults.bool(forKey: DefaultsKey.legacyAdblockEnabled) {
            return .adblock
        }
        if userDefaults.bool(forKey: DefaultsKey.legacyTrackingEnabled)
            || userDefaults.string(forKey: DefaultsKey.legacyTrackingGlobalMode) == SumiTrackingProtectionGlobalMode.enabled.rawValue {
            return .protection
        }
        return .off
    }
}

@MainActor
final class SumiProtectionCoordinator {
    static let shared = SumiProtectionCoordinator()

    let settings: SumiProtectionSettings
    private let trackingProtectionModule: SumiTrackingProtectionModule
    private let adBlockingModule: SumiAdBlockingModule
    private let moduleRegistry: SumiModuleRegistry
    private let siteNormalizer: SumiTrackingProtectionSiteNormalizer

    private var cancellables = Set<AnyCancellable>()
    private(set) var lastApplySummary: String?
    private(set) var lastApplyError: String?

    init(
        settings: SumiProtectionSettings = .shared,
        trackingProtectionModule: SumiTrackingProtectionModule = .shared,
        adBlockingModule: SumiAdBlockingModule = .shared,
        moduleRegistry: SumiModuleRegistry = .shared,
        siteNormalizer: SumiTrackingProtectionSiteNormalizer = SumiTrackingProtectionSiteNormalizer()
    ) {
        self.settings = settings
        self.trackingProtectionModule = trackingProtectionModule
        self.adBlockingModule = adBlockingModule
        self.moduleRegistry = moduleRegistry
        self.siteNormalizer = siteNormalizer
        syncLegacyModuleGates(for: settings.appliedLevel)
    }

    func setLevel(_ level: SumiProtectionLevel) {
        settings.setLevel(level)
    }

    var applyNeeded: Bool {
        let selectedLevel = settings.level
        guard selectedLevel == settings.appliedLevel else { return true }
        guard let requiredBundleProfileId = selectedLevel.preferredBundleProfileId else {
            return false
        }
        return activePreparedBundleProfileId != requiredBundleProfileId
    }

    func applySelectedLevel() async throws -> SumiProtectionApplyOutcome {
        let selectedLevel = settings.level
        let previousAppliedLevel = settings.appliedLevel
        syncLegacyModuleGates(for: selectedLevel)

        do {
            var installedBundleProfileId: String?
            if let requiredBundleProfileId = selectedLevel.preferredBundleProfileId {
                if activePreparedBundleProfileId != requiredBundleProfileId {
                    let manifest: AdblockCompiledGenerationManifest?
                    do {
                        manifest = try await adBlockingModule.installPreparedNativeRuleBundle(
                            profileId: requiredBundleProfileId
                        )
                    } catch {
                        throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                            profileId: requiredBundleProfileId,
                            detail: error.localizedDescription
                        )
                    }
                    guard let manifest,
                          Self.preparedBundleProfileId(in: manifest) == requiredBundleProfileId
                    else {
                        throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                            profileId: requiredBundleProfileId,
                            detail: "The installer did not publish the requested prepared bundle."
                        )
                    }
                }
                guard activePreparedBundleProfileId == requiredBundleProfileId else {
                    throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                        profileId: requiredBundleProfileId,
                        detail: "The active prepared bundle after install is \(activePreparedBundleProfileId ?? "nil")."
                    )
                }
                installedBundleProfileId = requiredBundleProfileId
            }

            settings.setAppliedLevel(selectedLevel)
            let summary = applySummary(
                selectedLevel: selectedLevel,
                installedBundleProfileId: installedBundleProfileId
            )
            lastApplySummary = summary
            lastApplyError = nil
            return SumiProtectionApplyOutcome(
                selectedLevel: selectedLevel,
                previousAppliedLevel: previousAppliedLevel,
                appliedLevel: settings.appliedLevel,
                installedBundleProfileId: installedBundleProfileId,
                summary: summary
            )
        } catch {
            syncLegacyModuleGates(for: previousAppliedLevel)
            let message: String
            if let applyError = error as? SumiProtectionApplyError {
                message = applyError.localizedDescription
            } else {
                message = "Could not apply \(selectedLevel.displayTitle): \(error.localizedDescription)"
            }
            lastApplySummary = nil
            lastApplyError = message
            throw SumiProtectionApplyError.applyFailed(message)
        }
    }

    @discardableResult
    func restoreAppliedLevelForStartup() async throws -> AdblockCompiledGenerationManifest? {
        let appliedLevel = settings.appliedLevel
        syncLegacyModuleGates(for: appliedLevel)
        guard let requiredBundleProfileId = appliedLevel.preferredBundleProfileId else {
            lastApplyError = nil
            return nil
        }

        do {
            let manifest = try await adBlockingModule.restorePreparedNativeRuleBundleForStartup(
                profileId: requiredBundleProfileId
            )
            guard let manifest,
                  Self.preparedBundleProfileId(in: manifest) == requiredBundleProfileId
            else {
                throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                    profileId: requiredBundleProfileId,
                    detail: "Startup restore did not publish the requested prepared bundle."
                )
            }
            lastApplySummary = "Restored \(appliedLevel.displayTitle) using prepared bundle \(requiredBundleProfileId)."
            lastApplyError = nil
            return manifest
        } catch {
            let message: String
            if let applyError = error as? SumiProtectionApplyError {
                message = applyError.localizedDescription
            } else {
                message = "Could not restore \(appliedLevel.displayTitle) at startup: \(error.localizedDescription)"
            }
            lastApplySummary = nil
            lastApplyError = message
            throw SumiProtectionApplyError.applyFailed(message)
        }
    }

    func recordReloadMarkingAfterApply(tabCount: Int) {
        guard var summary = lastApplySummary else { return }
        summary += " Marked \(tabCount) eligible web \(tabCount == 1 ? "tab" : "tabs") reload-required where the attachment plan changed."
        lastApplySummary = summary
    }

    func normalTabDecision(
        for url: URL?,
        profileId: UUID?
    ) -> SumiProtectionNormalTabDecision {
        let plan = rulePlan(for: url, profileId: profileId)
        let service = plan.ruleDefinitions.isEmpty
            ? nil
            : SumiContentBlockingService(policy: .enabled(ruleLists: plan.ruleDefinitions))
        return SumiProtectionNormalTabDecision(
            plan: plan,
            contentBlockingService: service
        )
    }

    func desiredAttachmentState(for url: URL?) -> SumiProtectionAttachmentState {
        rulePlan(for: url, profileId: nil).attachmentState
    }

    func rulePlan(
        for url: URL?,
        profileId: UUID?,
        includeExpensiveDiagnostics: Bool = false
    ) -> SumiProtectionRulePlan {
        makeRulePlan(
            for: url,
            profileId: profileId,
            includeExpensiveDiagnostics: includeExpensiveDiagnostics,
            loadRuleDefinitions: true
        )
    }

    func cachedRulePlan(
        for url: URL?,
        profileId: UUID?
    ) -> SumiProtectionRulePlan {
        makeRulePlan(
            for: url,
            profileId: profileId,
            includeExpensiveDiagnostics: false,
            loadRuleDefinitions: false
        )
    }

    private func makeRulePlan(
        for url: URL?,
        profileId: UUID?,
        includeExpensiveDiagnostics: Bool,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionRulePlan {
        let requestedLevel = settings.appliedLevel
        let eligibility = SumiAdblockSurfaceEligibility.evaluate(
            url: url,
            normalizer: siteNormalizer
        )
        let siteHost = eligibility.normalizedSiteHost
        let siteOverride = adBlockingModule.siteOverride(for: url)
        let siteAllowsProtection = requestedLevel != .off
            && eligibility.isEligible
            && siteOverride != .disabled

        var activeGroups = [SumiProtectionGroupKind]()
        var ruleCountsByGroup = [SumiProtectionGroupKind: Int]()
        var shardCountsByGroup = [SumiProtectionGroupKind: Int]()
        var expectedRuleListIdentifiers = [String]()
        var plannedDefinitions = [PlannedRuleDefinition]()
        var planningErrors = [String]()
        let manifest = adBlockingModule.activeManifestIfLoaded()
        let installedBundleProfileId = Self.installedBundleProfileId(from: manifest)
        let preparedBundleProfileId = manifest.flatMap { Self.preparedBundleProfileId(in: $0) }

        if siteAllowsProtection {
            if requestedLevel.requestedGroups.contains(.trackingNetwork) {
                if loadRuleDefinitions {
                    do {
                        let definitions = try trackingRuleDefinitions(profileId: profileId)
                        if !definitions.isEmpty {
                            activeGroups.append(.trackingNetwork)
                            ruleCountsByGroup[.trackingNetwork] = definitions.count
                            shardCountsByGroup[.trackingNetwork] = definitions.count
                            plannedDefinitions.append(contentsOf: definitions.map {
                                PlannedRuleDefinition(group: .trackingNetwork, source: .tracking, definition: $0)
                            })
                        }
                    } catch {
                        planningErrors.append("Tracking Protection rules unavailable: \(error.localizedDescription)")
                    }
                } else if cachedTrackingSourceAvailable() {
                    activeGroups.append(.trackingNetwork)
                }
            }

            if let requiredProfileId = requestedLevel.preferredBundleProfileId {
                if preparedBundleProfileId == requiredProfileId {
                    if loadRuleDefinitions {
                        do {
                            let definitions = try adBlockingModule.contentRuleListDefinitions(
                                for: requestedLevel.adblockRuleGroupKinds
                            )
                            let grouped = groupAdblockDefinitions(
                                definitions,
                                level: requestedLevel,
                                manifest: manifest
                            )
                            for entry in grouped where !entry.definitions.isEmpty {
                                activeGroups.append(entry.group)
                                ruleCountsByGroup[entry.group] = entry.ruleCount
                                shardCountsByGroup[entry.group] = entry.definitions.count
                                plannedDefinitions.append(contentsOf: entry.definitions.map {
                                    PlannedRuleDefinition(group: entry.group, source: .adblock, definition: $0)
                                })
                            }
                        } catch {
                            planningErrors.append("Native Adblock bundle rules unavailable: \(error.localizedDescription)")
                        }
                    } else if let manifest {
                        let grouped = Self.cachedAdblockGroups(
                            level: requestedLevel,
                            manifest: manifest
                        )
                        for entry in grouped where entry.shardCount > 0 {
                            activeGroups.append(entry.group)
                            ruleCountsByGroup[entry.group] = entry.ruleCount
                            shardCountsByGroup[entry.group] = entry.shardCount
                            expectedRuleListIdentifiers.append(contentsOf: entry.identifiers)
                        }
                    }
                } else {
                    planningErrors.append("Required prepared bundle profile \(requiredProfileId) is not active.")
                }
            }
        }

        let finalActiveGroups: [SumiProtectionGroupKind]
        let dedupeSummary: SumiProtectionDedupeSummary
        let overlapSummary: SumiProtectionOverlapSummary
        let ruleDefinitions: [SumiContentRuleListDefinition]
        if loadRuleDefinitions {
            let deduped = Self.deduped(plannedDefinitions)
            let activeGroupsAfterDedupe = Set(deduped.definitions.map(\.group))
            finalActiveGroups = activeGroups
                .filter { activeGroupsAfterDedupe.contains($0) }
                .uniqueSorted()
            expectedRuleListIdentifiers = deduped.definitions.map(\.definition.identifier).sorted()
            dedupeSummary = deduped.summary
            overlapSummary = Self.overlapSummary(
                for: plannedDefinitions,
                includeExpensiveDiagnostics: includeExpensiveDiagnostics
            )
            ruleDefinitions = deduped.definitions.map(\.definition)
        } else {
            finalActiveGroups = activeGroups.uniqueSorted()
            expectedRuleListIdentifiers = Array(Set(expectedRuleListIdentifiers)).sorted()
            dedupeSummary = .empty
            overlapSummary = .deferred
            ruleDefinitions = []
        }

        let requestedGroups = siteAllowsProtection ? requestedLevel.requestedGroups : []
        let inactiveGroups = requestedGroups
            .filter { !finalActiveGroups.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        let effectiveLevel = Self.effectiveLevel(for: finalActiveGroups)

        return SumiProtectionRulePlan(
            requestedLevel: requestedLevel,
            effectiveLevel: effectiveLevel,
            siteHost: siteHost,
            siteOverride: siteOverride,
            sitePolicyAllowsProtection: siteAllowsProtection,
            activeGroups: finalActiveGroups,
            inactiveGroups: inactiveGroups,
            bundleSource: manifest?.generationSource,
            nativeRuleBundleId: manifest?.nativeRuleBundleId,
            bundleProfileId: installedBundleProfileId,
            requiredBundleProfileId: requestedLevel.preferredBundleProfileId,
            activeGenerationId: manifest?.activeGenerationId,
            previousGenerationId: manifest?.previousGenerationId,
            previousGenerationRetained: manifest?.previousGenerationId != nil,
            ruleCountsByGroup: ruleCountsByGroup,
            shardCountsByGroup: shardCountsByGroup,
            expectedRuleListIdentifiers: expectedRuleListIdentifiers,
            dedupeSummary: dedupeSummary,
            overlapSummary: overlapSummary,
            ineligibleSurfaceReason: eligibility.ineligibleReason,
            planningErrors: planningErrors,
            ruleDefinitions: ruleDefinitions
        )
    }

    func currentTabDiagnostics(
        for url: URL?,
        appliedState: SumiProtectionAttachmentState?,
        reloadRequired: Bool,
        actualAttachedRuleListIdentifiers: [String]? = nil,
        contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary? = nil
    ) -> SumiProtectionCurrentTabDiagnostics {
        let plan = rulePlan(
            for: url,
            profileId: nil,
            includeExpensiveDiagnostics: true
        )
        let recordedApplied = appliedState?.attachedRuleListIdentifiers ?? []
        let lookupSucceeded = contentBlockingAssetSummary?.lookupSucceededIdentifiers ?? []
        let lookupFailed = contentBlockingAssetSummary?.lookupFailedIdentifiers ?? []
        let added = contentBlockingAssetSummary?.addedToUserContentControllerIdentifiers ?? []
        let actual = (
            actualAttachedRuleListIdentifiers
                ?? contentBlockingAssetSummary?.globalRuleListIdentifiers
                ?? recordedApplied
        ).sorted()
        let expected = plan.expectedRuleListIdentifiers
        let expectedSet = Set(expected)
        let actualSet = Set(actual)
        let missing = expected.filter { !actualSet.contains($0) }
        let unexpected = actual.filter { !expectedSet.contains($0) }

        return SumiProtectionCurrentTabDiagnostics(
            urlString: url?.absoluteString,
            host: url?.host,
            normalizedSiteKey: plan.siteHost,
            protectionLevel: plan.requestedLevel,
            effectiveProtectionLevel: plan.effectiveLevel,
            activeGroups: plan.activeGroups,
            inactiveGroups: plan.inactiveGroups,
            desiredGroups: plan.requestedLevel.requestedGroups,
            perSiteProtectionEnabled: plan.sitePolicyAllowsProtection,
            reloadRequired: reloadRequired,
            generationSource: plan.bundleSource,
            nativeRuleBundleId: plan.nativeRuleBundleId,
            bundleProfileId: plan.bundleProfileId,
            requiredBundleProfileId: plan.requiredBundleProfileId,
            trackingGroupActive: plan.trackingGroupActive,
            adblockGroupActive: plan.adblockGroupActive,
            nativeCSSGroupActive: plan.nativeCSSGroupActive,
            ruleCountsByGroup: plan.ruleCountsByGroup,
            shardCountsByGroup: plan.shardCountsByGroup,
            dedupeSummary: plan.dedupeSummary,
            overlapSummary: plan.overlapSummary,
            expectedRuleListIdentifiers: expected,
            lookupSucceededIdentifiers: lookupSucceeded,
            lookupFailedIdentifiers: lookupFailed,
            addedToUserContentControllerIdentifiers: added,
            recordedAppliedRuleListIdentifiers: recordedApplied,
            actualAttachedRuleListIdentifiers: actual,
            missingRuleListIdentifiers: missing,
            missingAfterAttachmentIdentifiers: missing,
            unexpectedOldRuleListIdentifiers: unexpected,
            activeGenerationId: plan.activeGenerationId,
            appliedProtectionGenerationId: appliedState?.activeGenerationId,
            appliedProtectionGroups: appliedState?.activeGroups ?? [],
            previousGenerationId: plan.previousGenerationId,
            previousGenerationRetained: plan.previousGenerationRetained,
            ruleListIdentifierSamplesByGroup: Self.ruleListIdentifierSamplesByGroup(for: plan),
            eligibleSurfaceReason: plan.ineligibleSurfaceReason == nil ? "eligible http(s) web surface" : nil,
            ineligibleSurfaceReason: plan.ineligibleSurfaceReason,
            currentProcessResidentMemoryBytes: Self.currentProcessResidentMemoryBytes(),
            planningErrors: plan.planningErrors
        )
    }

    func globalDiagnostics() -> SumiProtectionGlobalDiagnostics {
        let manifest = adBlockingModule.activeManifestIfLoaded()
        let selectedLevel = settings.level
        let installedBundleProfileId = Self.installedBundleProfileId(from: manifest)
        let activePreparedProfileId = manifest.flatMap { Self.preparedBundleProfileId(in: $0) }
        let requiredBundleProfileId = selectedLevel.preferredBundleProfileId
        let preparedBundleDiscovery = requiredBundleProfileId.map {
            adBlockingModule.preparedNativeRuleBundleDiscovery(profileId: $0)
        }
        let trackingSourceAvailable = cachedTrackingSourceAvailable()
        let availableGroups = globallyAvailableGroups(
            manifest: manifest,
            trackingSourceAvailable: trackingSourceAvailable
        )
        let adblockBundleAvailable = requiredBundleProfileId.map {
            activePreparedProfileId == $0
        } ?? true

        return SumiProtectionGlobalDiagnostics(
            selectedProtectionLevel: selectedLevel,
            appliedProtectionLevel: settings.appliedLevel,
            generationSource: manifest?.generationSource,
            nativeRuleBundleId: manifest?.nativeRuleBundleId,
            bundleProfileId: installedBundleProfileId,
            activeGenerationId: manifest?.activeGenerationId,
            requiredBundleProfileId: requiredBundleProfileId,
            preparedBundleAvailable: preparedBundleDiscovery?.isAvailable ?? true,
            preparedBundleSource: preparedBundleDiscovery?.source,
            searchedBundlePaths: preparedBundleDiscovery?.searchedPaths ?? [],
            applyNeeded: applyNeeded,
            lastApplySummary: lastApplySummary,
            lastApplyError: lastApplyError,
            globalGroupsAvailable: availableGroups,
            trackingSourceAvailable: trackingSourceAvailable,
            adblockBundleAvailable: adblockBundleAvailable
        )
    }

#if DEBUG
    func copyDiagnosticsReport(
        for url: URL?,
        currentTabDiagnostics: SumiProtectionCurrentTabDiagnostics?,
        targetDescription: String = "current tab",
        requestingURL: URL? = nil
    ) -> String {
        let global = globalDiagnostics()
        let plan = rulePlan(
            for: url,
            profileId: nil,
            includeExpensiveDiagnostics: true
        )
        let targetURLString = url?.absoluteString ?? "nil"
        let actualAttachedIdentifiers = currentTabDiagnostics?.actualAttachedRuleListIdentifiers ?? []
        let missingIdentifiers = currentTabDiagnostics?.missingRuleListIdentifiers ?? []
        let lookupSucceededIdentifiers = currentTabDiagnostics?.lookupSucceededIdentifiers ?? []
        let lookupFailedIdentifiers = currentTabDiagnostics?.lookupFailedIdentifiers ?? []
        let addedIdentifiers = currentTabDiagnostics?.addedToUserContentControllerIdentifiers ?? []
        let reloadRequired = currentTabDiagnostics?.reloadRequired ?? false
        var lines = [
            "Sumi Adblock & Protection Copy Diagnostics",
            "timestamp=\(Self.iso8601Timestamp(Date()))",
            "",
            "Global protection state",
            "protectionLevel=\(global.selectedProtectionLevel.rawValue)",
            "appliedProtectionLevel=\(global.appliedProtectionLevel.rawValue)",
            "generationSource=\(global.generationSource?.rawValue ?? "nil")",
            "nativeRuleBundleId=\(global.nativeRuleBundleId ?? "nil")",
            "bundleProfileId=\(global.bundleProfileId ?? "nil")",
            "activeGenerationId=\(global.activeGenerationId ?? "nil")",
            "requiredBundleProfileId=\(global.requiredBundleProfileId ?? "nil")",
            "preparedBundleAvailable=\(global.preparedBundleAvailable)",
            "preparedBundleSource=\(global.preparedBundleSource?.rawValue ?? "nil")",
            "searchedBundlePaths=\(Self.renderSearchedBundlePaths(global.searchedBundlePaths))",
            "applyNeeded=\(global.applyNeeded)",
            "lastApplySummary=\(global.lastApplySummary ?? "nil")",
            "lastApplyError=\(global.lastApplyError ?? "nil")",
            "globalGroupsAvailable=\(global.globalGroupsAvailable.map(\.rawValue).joined(separator: ","))",
            "trackingSourceAvailable=\(global.trackingSourceAvailable)",
            "adblockBundleAvailable=\(global.adblockBundleAvailable)",
            "",
            "Target page plan",
            "targetSource=\(targetDescription)",
            "targetURL=\(targetURLString)",
            "diagnosticsTargetURL=\(targetURLString)",
            "requestingURL=\(requestingURL?.absoluteString ?? "nil")",
            "eligible=\(plan.ineligibleSurfaceReason == nil)",
            "ineligibleSurfaceReason=\(plan.ineligibleSurfaceReason ?? "nil")",
            "requestedProtectionLevelForPage=\(plan.requestedLevel.rawValue)",
            "effectiveProtectionLevel=\(plan.effectiveLevel.rawValue)",
            "activeGroups=\(plan.activeGroups.map(\.rawValue).joined(separator: ","))",
            "inactiveGroups=\(plan.inactiveGroups.map(\.rawValue).joined(separator: ","))",
            "desiredGroups=\(plan.requestedLevel.requestedGroups.map(\.rawValue).joined(separator: ","))",
            "trackingGroupActive=\(plan.trackingGroupActive)",
            "adblockGroupActive=\(plan.adblockGroupActive)",
            "nativeCSSGroupActive=\(plan.nativeCSSGroupActive)",
            "ruleCountsByGroup=\(SumiProtectionCurrentTabDiagnostics.renderCounts(plan.ruleCountsByGroup))",
            "shardCountsByGroup=\(SumiProtectionCurrentTabDiagnostics.renderCounts(plan.shardCountsByGroup))",
            "expectedRuleListIdentifiers=\(plan.expectedRuleListIdentifiers.joined(separator: ","))",
            "lookupSucceededIdentifiers=\(lookupSucceededIdentifiers.joined(separator: ","))",
            "lookupFailedIdentifiers=\(lookupFailedIdentifiers.joined(separator: ","))",
            "addedToUserContentControllerIdentifiers=\(addedIdentifiers.joined(separator: ","))",
            "attachedIdentifiers=\(actualAttachedIdentifiers.joined(separator: ","))",
            "missingIdentifiers=\(missingIdentifiers.joined(separator: ","))",
            "missingAfterAttachmentIdentifiers=\(missingIdentifiers.joined(separator: ","))",
            "ruleListIdentifierSamplesByGroup=\(SumiProtectionCurrentTabDiagnostics.renderIdentifierSamples(Self.ruleListIdentifierSamplesByGroup(for: plan)))",
            "reloadRequired=\(reloadRequired)",
            "dedupeSummary=\(plan.dedupeSummary.reportLine)",
            "overlapSummary=\(plan.overlapSummary.reportLine)",
            "planningErrors=\(plan.planningErrors.joined(separator: " | "))",
        ]
        if let currentTabDiagnostics {
            lines.append(currentTabDiagnostics.developerReport)
        } else {
            lines.append("Sumi Adblock & Protection current-tab diagnostics\ncurrentTab=nil")
        }
        return lines.joined(separator: "\n")
    }
#endif

    func siteOverride(for url: URL?) -> SumiAdblockSiteOverride {
        adBlockingModule.siteOverride(for: url)
    }

    func setSiteOverride(_ override: SumiAdblockSiteOverride, for url: URL?) {
        adBlockingModule.setSiteOverride(override, for: url)
    }

    func sitePolicyChangesPublisher() -> AnyPublisher<Void, Never> {
        adBlockingModule.sitePolicyChangesPublisher()
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        SumiAdblockSurfaceEligibility.evaluate(url: url, normalizer: siteNormalizer)
    }

    private var activePreparedBundleProfileId: String? {
        let manifest = adBlockingModule.activeManifestIfLoaded()
        return manifest.flatMap { Self.preparedBundleProfileId(in: $0) }
    }

    private func syncLegacyModuleGates(for level: SumiProtectionLevel) {
        trackingProtectionModule.setEnabled(level != .off)
        adBlockingModule.setEnabled(level == .adblock || level == .extreme)
    }

    private func applySummary(
        selectedLevel: SumiProtectionLevel,
        installedBundleProfileId: String?
    ) -> String {
        if let installedBundleProfileId {
            return "Applied \(selectedLevel.displayTitle) using prepared bundle \(installedBundleProfileId)."
        }
        return "Applied \(selectedLevel.displayTitle)."
    }

    private func cachedTrackingSourceAvailable() -> Bool {
        trackingProtectionModule.isEnabled
    }

    private func globallyAvailableGroups(
        manifest: AdblockCompiledGenerationManifest?,
        trackingSourceAvailable: Bool
    ) -> [SumiProtectionGroupKind] {
        var groups = [SumiProtectionGroupKind]()
        if trackingSourceAvailable {
            groups.append(.trackingNetwork)
        }

        if let manifest,
           Self.preparedBundleProfileId(in: manifest) != nil {
            groups.append(contentsOf: Self.cachedAdblockGroups(level: .adblock, manifest: manifest).map(\.group))
            groups.append(contentsOf: Self.cachedAdblockGroups(level: .extreme, manifest: manifest).map(\.group))
        }

        return groups.uniqueSorted()
    }

    private func trackingRuleDefinitions(profileId: UUID?) throws -> [SumiContentRuleListDefinition] {
        guard let assets = trackingProtectionModule.contentBlockingAssetsIfEnabled() else { return [] }
        let policy = SumiTrackingProtectionPolicy(
            globalMode: .enabled,
            enabledSiteHosts: [],
            disabledSiteHosts: []
        )
        return try assets.ruleListProvider.ruleListSet(
            for: policy,
            profileId: profileId
        ).allDefinitions
    }

    private func groupAdblockDefinitions(
        _ definitions: [SumiContentRuleListDefinition],
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> [(group: SumiProtectionGroupKind, definitions: [SumiContentRuleListDefinition], ruleCount: Int)] {
        guard let manifest,
              Self.preparedBundleProfileId(in: manifest) != nil
        else { return [] }
        let definitionsByIdentifier = definitions.reduce(into: [String: SumiContentRuleListDefinition]()) { result, definition in
            result[definition.identifier] = definition
        }
        return Self.cachedAdblockGroups(level: level, manifest: manifest)
            .compactMap { cachedGroup in
                let definitions = cachedGroup.identifiers.compactMap { definitionsByIdentifier[$0] }
                guard !definitions.isEmpty else { return nil }
                return (
                    group: cachedGroup.group,
                    definitions: definitions,
                    ruleCount: cachedGroup.ruleCount
                )
            }
    }

    private static func cachedAdblockGroups(
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest
    ) -> [CachedAdblockGroup] {
        guard let bundleProfileId = preparedBundleProfileId(in: manifest) else { return [] }
        let groups = manifest.allNativeShards.reduce(into: [SumiProtectionGroupKind: CachedAdblockGroup]()) { result, shard in
            guard let group = protectionGroup(
                for: shard.kind,
                bundleProfileId: bundleProfileId,
                level: level
            ) else { return }
            let existing = result[group]
            result[group] = CachedAdblockGroup(
                group: group,
                identifiers: (existing?.identifiers ?? []) + [shard.webKitIdentifier],
                shardCount: (existing?.shardCount ?? 0) + 1,
                ruleCount: (existing?.ruleCount ?? 0) + shard.approximateRuleCount
            )
        }
        return groups.values.sorted { $0.group.rawValue < $1.group.rawValue }
    }

    private static func protectionGroup(
        for shardKind: AdblockCompiledRuleGroupKind,
        bundleProfileId: String,
        level: SumiProtectionLevel
    ) -> SumiProtectionGroupKind? {
        switch (bundleProfileId, shardKind, level) {
        case (SumiProtectionBundleProfile.adblock, .network, .adblock):
            return .adblockAdsPrivacyNetwork
        case (SumiProtectionBundleProfile.extreme, .network, .extreme):
            return .maximumNativeNetwork
        case (SumiProtectionBundleProfile.extreme, .nativeCosmeticCSS, .extreme):
            return .maximumNativeCSS
        default:
            return nil
        }
    }

    private static func preparedBundleProfileId(
        in manifest: AdblockCompiledGenerationManifest
    ) -> String? {
        guard !manifest.activeGenerationId.isEmpty,
              manifest.generationSource.isPreparedBundleSource
        else { return nil }
        return installedBundleProfileId(from: manifest)
    }

    private static func installedBundleProfileId(
        from manifest: AdblockCompiledGenerationManifest?
    ) -> String? {
        guard let manifest else { return nil }
        if let bundleProfileId = manifest.bundleProfileId, !bundleProfileId.isEmpty {
            return bundleProfileId
        }
        if let nativeProfile = manifest.nativeProfile?.rawValue, !nativeProfile.isEmpty {
            return nativeProfile
        }
        return inferredBundleProfileId(from: manifest.nativeRuleBundleId)
    }

    private static func inferredBundleProfileId(from nativeRuleBundleId: String?) -> String? {
        guard let nativeRuleBundleId else { return nil }
        for profileId in [SumiProtectionBundleProfile.adblock, SumiProtectionBundleProfile.extreme] {
            if nativeRuleBundleId.contains(profileId) {
                return profileId
            }
        }
        return nil
    }

    private static func effectiveLevel(
        for activeGroups: [SumiProtectionGroupKind]
    ) -> SumiProtectionLevel {
        if activeGroups.contains(.maximumNativeNetwork) || activeGroups.contains(.maximumNativeCSS) {
            return .extreme
        }
        if activeGroups.contains(.adblockAdsPrivacyNetwork) {
            return .adblock
        }
        if activeGroups.contains(.trackingNetwork) {
            return .protection
        }
        return .off
    }

    private static func deduped(
        _ plannedDefinitions: [PlannedRuleDefinition]
    ) -> (definitions: [PlannedRuleDefinition], summary: SumiProtectionDedupeSummary) {
        var seenIdentifiers = Set<String>()
        var seenCanonicalHashes = [String: PlannedRuleDefinition]()
        var seenGroupHashes = Set<String>()
        var output = [PlannedRuleDefinition]()
        var duplicateIdentifierCount = 0
        var duplicateCanonicalCount = 0
        var duplicateGroupHashCount = 0
        var canonicalUnavailableCount = 0
        var removedIdentifiers = [String]()

        for planned in plannedDefinitions {
            let identifier = planned.definition.identifier
            guard seenIdentifiers.insert(identifier).inserted else {
                duplicateIdentifierCount += 1
                removedIdentifiers.append(identifier)
                continue
            }

            let groupHashKey = "\(planned.group.rawValue):\(planned.definition.contentHash)"
            guard seenGroupHashes.insert(groupHashKey).inserted else {
                duplicateGroupHashCount += 1
                removedIdentifiers.append(identifier)
                continue
            }

            if let canonicalHash = canonicalWebKitJSONHash(planned.definition.encodedContentRuleList) {
                if seenCanonicalHashes[canonicalHash] != nil {
                    duplicateCanonicalCount += 1
                    removedIdentifiers.append(identifier)
                    continue
                }
                seenCanonicalHashes[canonicalHash] = planned
            } else {
                canonicalUnavailableCount += 1
            }

            output.append(planned)
        }

        return (
            output,
            SumiProtectionDedupeSummary(
                inputRuleListCount: plannedDefinitions.count,
                finalRuleListCount: output.count,
                duplicateIdentifierCountRemoved: duplicateIdentifierCount,
                duplicateCanonicalJSONCountRemoved: duplicateCanonicalCount,
                duplicateGroupContentHashCountRemoved: duplicateGroupHashCount,
                canonicalJSONUnavailableCount: canonicalUnavailableCount,
                removedIdentifiers: removedIdentifiers.sorted()
            )
        )
    }

    private static func overlapSummary(
        for plannedDefinitions: [PlannedRuleDefinition],
        includeExpensiveDiagnostics: Bool
    ) -> SumiProtectionOverlapSummary {
        let tracking = plannedDefinitions.filter { $0.source == .tracking }
        let adblock = plannedDefinitions.filter { $0.source == .adblock }
        guard !tracking.isEmpty, !adblock.isEmpty else {
            return SumiProtectionOverlapSummary(
                exactCanonicalOverlapCount: 0,
                domainResourceOverlapCount: 0,
                exactComparisonAvailable: false,
                notes: ["Tracking and Adblock are not both active in this plan."]
            )
        }
        guard includeExpensiveDiagnostics else {
            return .deferred
        }

        let trackingCanonical = Set(tracking.compactMap {
            canonicalWebKitJSONHash($0.definition.encodedContentRuleList)
        })
        let adblockCanonical = Set(adblock.compactMap {
            canonicalWebKitJSONHash($0.definition.encodedContentRuleList)
        })
        let exactComparisonAvailable = trackingCanonical.count == tracking.count
            && adblockCanonical.count == adblock.count

        let trackingDomains = Set(tracking.flatMap {
            urlFilterTokens(in: $0.definition.encodedContentRuleList)
        })
        let adblockDomains = Set(adblock.flatMap {
            urlFilterTokens(in: $0.definition.encodedContentRuleList)
        })
        var notes = [String]()
        if !exactComparisonAvailable {
            notes.append("Exact cross-source dedupe is unavailable for rule lists that cannot be safely canonicalized.")
        }
        if trackingDomains.isEmpty || adblockDomains.isEmpty {
            notes.append("Domain/resource overlap is heuristic because not every WebKit trigger exposes a host token.")
        }

        return SumiProtectionOverlapSummary(
            exactCanonicalOverlapCount: trackingCanonical.intersection(adblockCanonical).count,
            domainResourceOverlapCount: trackingDomains.intersection(adblockDomains).count,
            exactComparisonAvailable: exactComparisonAvailable,
            notes: notes
        )
    }

    private static func ruleListIdentifierSamplesByGroup(
        for plan: SumiProtectionRulePlan
    ) -> [SumiProtectionGroupKind: [String]] {
        var samples = [SumiProtectionGroupKind: [String]]()
        for group in plan.activeGroups {
            let identifiers: [String]
            switch group {
            case .trackingNetwork:
                identifiers = plan.expectedRuleListIdentifiers.filter {
                    !$0.hasPrefix("sumi.adblock.")
                }
            case .adblockAdsPrivacyNetwork, .maximumNativeNetwork:
                identifiers = plan.expectedRuleListIdentifiers.filter {
                    $0.hasPrefix("sumi.adblock.network.")
                }
            case .maximumNativeCSS:
                identifiers = plan.expectedRuleListIdentifiers.filter {
                    $0.hasPrefix("sumi.adblock.nativeCSS.")
                }
            }
            samples[group] = identifiers
                .prefix(4)
                .map(redactedRuleListIdentifier)
        }
        return samples
    }

    private static func redactedRuleListIdentifier(_ identifier: String) -> String {
        let parts = identifier.split(separator: ".").map(String.init)
        guard parts.count > 6 else { return identifier }
        return (Array(parts.prefix(4)) + ["..."] + Array(parts.suffix(2))).joined(separator: ".")
    }

    private static func canonicalWebKitJSONHash(_ encodedContentRuleList: String) -> String? {
        guard let data = encodedContentRuleList.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let canonicalData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
              )
        else { return nil }
        return sha256Hex(canonicalData)
    }

    private static func urlFilterTokens(in encodedContentRuleList: String) -> [String] {
        guard let data = encodedContentRuleList.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return array.compactMap { rule in
            guard let trigger = rule["trigger"] as? [String: Any],
                  let filter = trigger["url-filter"] as? String
            else { return nil }
            return domainToken(from: filter)
        }
    }

    private static func domainToken(from filter: String) -> String? {
        let lowercased = filter.lowercased()
        let pieces = lowercased.split { character in
            !(character.isLetter || character.isNumber || character == "." || character == "-")
        }
        return pieces
            .map(String.init)
            .first { token in
                token.contains(".")
                    && !token.hasPrefix(".")
                    && !token.hasSuffix(".")
                    && token.count > 3
            }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func currentProcessResidentMemoryBytes() -> UInt64? {
#if DEBUG
        return AdblockProcessMemorySampler.residentMemoryBytes()
#else
        return nil
#endif
    }

    private static func renderSearchedBundlePaths(
        _ paths: [SumiPreparedAdblockBundleSearchPath]
    ) -> String {
        paths.map { path in
            "\(path.source.rawValue):path=\(path.path);exists=\(path.exists);rejected=\(path.rejectionReason ?? "nil")"
        }.joined(separator: " | ")
    }

    private static func iso8601Timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private enum SumiProtectionApplyError: LocalizedError {
    case requiredPreparedBundleUnavailable(profileId: String, detail: String)
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .requiredPreparedBundleUnavailable(let profileId, let detail):
            return "Required prepared bundle profile \(profileId) is unavailable. \(detail)"
        case .applyFailed(let message):
            return message
        }
    }
}

private enum PlannedRuleSource: Sendable {
    case tracking
    case adblock
}

private struct PlannedRuleDefinition: Equatable, Sendable {
    let group: SumiProtectionGroupKind
    let source: PlannedRuleSource
    let definition: SumiContentRuleListDefinition
}

private struct CachedAdblockGroup: Equatable, Sendable {
    let group: SumiProtectionGroupKind
    let identifiers: [String]
    let shardCount: Int
    let ruleCount: Int
}

private extension SumiContentRuleListDefinition {
    var identifier: String {
        storeIdentifierOverride ?? name
    }
}

private extension AdblockRuleGenerationSource {
    var isPreparedBundleSource: Bool {
        switch self {
        case .embeddedBundle, .developmentBundle, .futureRemoteBundle:
            return true
        case .runtimeGenerated:
            return false
        }
    }
}

private extension Array where Element == SumiProtectionGroupKind {
    func uniqueSorted() -> [SumiProtectionGroupKind] {
        Array(Set(self)).sorted { $0.rawValue < $1.rawValue }
    }
}
