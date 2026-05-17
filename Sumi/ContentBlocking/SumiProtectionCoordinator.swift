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
    let recordedAppliedRuleListIdentifiers: [String]
    let actualAttachedRuleListIdentifiers: [String]
    let missingRuleListIdentifiers: [String]
    let unexpectedOldRuleListIdentifiers: [String]
    let activeGenerationId: String?
    let previousGenerationId: String?
    let previousGenerationRetained: Bool
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
            "recordedAppliedRuleListIdentifiers=\(recordedAppliedRuleListIdentifiers.joined(separator: ","))",
            "actualAttachedRuleListIdentifiers=\(actualAttachedRuleListIdentifiers.joined(separator: ","))",
            "missingRuleListIdentifiers=\(missingRuleListIdentifiers.joined(separator: ","))",
            "unexpectedOldRuleListIdentifiers=\(unexpectedOldRuleListIdentifiers.joined(separator: ","))",
            "activeGenerationId=\(activeGenerationId ?? "nil")",
            "previousGenerationId=\(previousGenerationId ?? "nil")",
            "previousGenerationRetained=\(previousGenerationRetained)",
            "eligibleSurfaceReason=\(eligibleSurfaceReason ?? "nil")",
            "ineligibleSurfaceReason=\(ineligibleSurfaceReason ?? "nil")",
            "currentProcessResidentMemoryBytes=\(currentProcessResidentMemoryBytes.map(String.init) ?? "nil")",
            "planningErrors=\(planningErrors.joined(separator: " | "))",
        ].joined(separator: "\n")
    }

    private static func renderCounts(_ counts: [SumiProtectionGroupKind: Int]) -> String {
        SumiProtectionGroupKind.allCases
            .compactMap { group in
                counts[group].map { "\(group.rawValue):\($0)" }
            }
            .joined(separator: ",")
    }
}

@MainActor
final class SumiProtectionSettings: ObservableObject {
    static let shared = SumiProtectionSettings()

    private enum DefaultsKey {
        static let level = "settings.protection.level"
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

    private let userDefaults: UserDefaults
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let rawLevel = userDefaults.string(forKey: DefaultsKey.level),
           let decodedLevel = SumiProtectionLevel(rawValue: rawLevel) {
            level = decodedLevel
        } else {
            level = Self.migratedLevel(from: userDefaults)
            userDefaults.set(level.rawValue, forKey: DefaultsKey.level)
        }
    }

    func setLevel(_ level: SumiProtectionLevel) {
        guard self.level != level else { return }
        self.level = level
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
        syncLegacyModuleGates()
        settings.changesPublisher
            .sink { [weak self] in
                self?.syncLegacyModuleGates()
            }
            .store(in: &cancellables)
    }

    func setLevel(_ level: SumiProtectionLevel) {
        settings.setLevel(level)
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
        let requestedLevel = settings.level
        let eligibility = SumiAdblockSurfaceEligibility.evaluate(
            url: url,
            normalizer: siteNormalizer
        )
        let siteHost = eligibility.normalizedSiteHost
        let siteOverride = adBlockingModule.siteOverride(for: url)
        let legacyTrackingOverride = requestedLevel == .off
            ? nil
            : trackingProtectionModule.siteOverrideIfEnabled(for: url)
        let siteAllowsProtection = requestedLevel != .off
            && eligibility.isEligible
            && siteOverride != .disabled
            && legacyTrackingOverride != .disabled

        var activeGroups = [SumiProtectionGroupKind]()
        var ruleCountsByGroup = [SumiProtectionGroupKind: Int]()
        var shardCountsByGroup = [SumiProtectionGroupKind: Int]()
        var plannedDefinitions = [PlannedRuleDefinition]()
        var planningErrors = [String]()

        if siteAllowsProtection {
            if requestedLevel.requestedGroups.contains(.trackingNetwork) {
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
            }

            if let requiredProfileId = requestedLevel.preferredBundleProfileId {
                let manifest = adBlockingModule.activeManifestIfLoaded()
                let activeProfileId = manifest?.bundleProfileId
                    ?? manifest?.nativeProfile?.rawValue
                if activeProfileId == requiredProfileId {
                    do {
                        let definitions = try adBlockingModule.contentRuleListDefinitions(
                            for: requestedLevel.adblockRuleGroupKinds
                        )
                        let grouped = groupAdblockDefinitions(
                            definitions,
                            level: requestedLevel,
                            manifest: manifest
                        )
                        for entry in grouped {
                            if !entry.definitions.isEmpty {
                                activeGroups.append(entry.group)
                                ruleCountsByGroup[entry.group] = entry.ruleCount
                                shardCountsByGroup[entry.group] = entry.definitions.count
                                plannedDefinitions.append(contentsOf: entry.definitions.map {
                                    PlannedRuleDefinition(group: entry.group, source: .adblock, definition: $0)
                                })
                            }
                        }
                    } catch {
                        planningErrors.append("Native Adblock bundle rules unavailable: \(error.localizedDescription)")
                    }
                } else {
                    planningErrors.append("Required native bundle profile \(requiredProfileId) is not active.")
                }
            }
        }

        let deduped = Self.deduped(plannedDefinitions)
        let activeGroupsAfterDedupe = Set(deduped.definitions.map(\.group))
        let finalActiveGroups = activeGroups
            .filter { activeGroupsAfterDedupe.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        let requestedGroups = siteAllowsProtection ? requestedLevel.requestedGroups : []
        let inactiveGroups = requestedGroups
            .filter { !finalActiveGroups.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        let effectiveLevel = Self.effectiveLevel(for: finalActiveGroups)
        let manifest = adBlockingModule.activeManifestIfLoaded()

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
            bundleProfileId: manifest?.bundleProfileId ?? manifest?.nativeProfile?.rawValue,
            requiredBundleProfileId: requestedLevel.preferredBundleProfileId,
            activeGenerationId: manifest?.activeGenerationId,
            previousGenerationId: manifest?.previousGenerationId,
            previousGenerationRetained: manifest?.previousGenerationId != nil,
            ruleCountsByGroup: ruleCountsByGroup,
            shardCountsByGroup: shardCountsByGroup,
            expectedRuleListIdentifiers: deduped.definitions.map(\.definition.identifier).sorted(),
            dedupeSummary: deduped.summary,
            overlapSummary: Self.overlapSummary(
                for: plannedDefinitions,
                includeExpensiveDiagnostics: includeExpensiveDiagnostics
            ),
            ineligibleSurfaceReason: eligibility.ineligibleReason,
            planningErrors: planningErrors,
            ruleDefinitions: deduped.definitions.map(\.definition)
        )
    }

    func currentTabDiagnostics(
        for url: URL?,
        appliedState: SumiProtectionAttachmentState?,
        reloadRequired: Bool,
        actualAttachedRuleListIdentifiers: [String]? = nil
    ) -> SumiProtectionCurrentTabDiagnostics {
        let plan = rulePlan(
            for: url,
            profileId: nil,
            includeExpensiveDiagnostics: true
        )
        let recordedApplied = appliedState?.attachedRuleListIdentifiers ?? []
        let actual = (actualAttachedRuleListIdentifiers ?? recordedApplied).sorted()
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
            recordedAppliedRuleListIdentifiers: recordedApplied,
            actualAttachedRuleListIdentifiers: actual,
            missingRuleListIdentifiers: missing,
            unexpectedOldRuleListIdentifiers: unexpected,
            activeGenerationId: plan.activeGenerationId,
            previousGenerationId: plan.previousGenerationId,
            previousGenerationRetained: plan.previousGenerationRetained,
            eligibleSurfaceReason: plan.ineligibleSurfaceReason == nil ? "eligible http(s) web surface" : nil,
            ineligibleSurfaceReason: plan.ineligibleSurfaceReason,
            currentProcessResidentMemoryBytes: Self.currentProcessResidentMemoryBytes(),
            planningErrors: plan.planningErrors
        )
    }

#if DEBUG
    func copyDiagnosticsReport(
        for url: URL?,
        currentTabDiagnostics: SumiProtectionCurrentTabDiagnostics?,
        targetDescription: String = "current tab",
        requestingURL: URL? = nil
    ) -> String {
        let plan = rulePlan(
            for: url,
            profileId: nil,
            includeExpensiveDiagnostics: true
        )
        let targetURLString = url?.absoluteString ?? "nil"
        var lines = [
            "Sumi Adblock & Protection Copy Diagnostics",
            "timestamp=\(Self.iso8601Timestamp(Date()))",
            "targetSource=\(targetDescription)",
            "targetURL=\(targetURLString)",
            "diagnosticsTargetURL=\(targetURLString)",
            "requestingURL=\(requestingURL?.absoluteString ?? "nil")",
            "protectionLevel=\(plan.requestedLevel.rawValue)",
            "effectiveProtectionLevel=\(plan.effectiveLevel.rawValue)",
            "activeGroups=\(plan.activeGroups.map(\.rawValue).joined(separator: ","))",
            "inactiveGroups=\(plan.inactiveGroups.map(\.rawValue).joined(separator: ","))",
            "generationSource=\(plan.bundleSource?.rawValue ?? "nil")",
            "nativeRuleBundleId=\(plan.nativeRuleBundleId ?? "nil")",
            "bundleProfileId=\(plan.bundleProfileId ?? "nil")",
            "trackingGroupActive=\(plan.trackingGroupActive)",
            "adblockGroupActive=\(plan.adblockGroupActive)",
            "nativeCSSGroupActive=\(plan.nativeCSSGroupActive)",
            "dedupeSummary=\(plan.dedupeSummary.reportLine)",
            "overlapSummary=\(plan.overlapSummary.reportLine)",
            "ineligibleSurfaceReason=\(plan.ineligibleSurfaceReason ?? "nil")",
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

    private func syncLegacyModuleGates() {
        let level = settings.level
        trackingProtectionModule.setEnabled(level != .off)
        adBlockingModule.setEnabled(level == .adblock || level == .extreme)
        if let preferredBundleProfileId = level.preferredBundleProfileId {
            adBlockingModule.ensurePreferredNativeRuleBundleInstalled(profileId: preferredBundleProfileId)
        }
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
        guard let manifest else { return [] }
        let definitionsByIdentifier = definitions.reduce(into: [String: SumiContentRuleListDefinition]()) { result, definition in
            result[definition.identifier] = definition
        }
        switch level {
        case .adblock:
            let network = manifest.networkShards.compactMap { definitionsByIdentifier[$0.webKitIdentifier] }
            return [
                (
                    group: .adblockAdsPrivacyNetwork,
                    definitions: network,
                    ruleCount: manifest.networkShards.reduce(0) { $0 + $1.approximateRuleCount }
                ),
            ]
        case .extreme:
            let network = manifest.networkShards.compactMap { definitionsByIdentifier[$0.webKitIdentifier] }
            let nativeCSS = manifest.nativeCSSShards.compactMap { definitionsByIdentifier[$0.webKitIdentifier] }
            return [
                (
                    group: .maximumNativeNetwork,
                    definitions: network,
                    ruleCount: manifest.networkShards.reduce(0) { $0 + $1.approximateRuleCount }
                ),
                (
                    group: .maximumNativeCSS,
                    definitions: nativeCSS,
                    ruleCount: manifest.nativeCSSShards.reduce(0) { $0 + $1.approximateRuleCount }
                ),
            ]
        case .off, .protection:
            return []
        }
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

    private static func iso8601Timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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

private extension SumiContentRuleListDefinition {
    var identifier: String {
        storeIdentifierOverride ?? name
    }
}
