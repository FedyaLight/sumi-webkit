import Combine
import CryptoKit
import Foundation
import OSLog

enum SumiProtectionBundleProfile {
    static let unified = "adguardAdsPrivacy"
    static let adblock = "adguardAdsPrivacy"
}

enum SumiProtectionLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case protection
    case adblock

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .off:
            return "Off"
        case .protection:
            return "Protection"
        case .adblock:
            return "Adblock"
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
        }
    }

    var preferredBundleProfileId: String? {
        switch self {
        case .off:
            return nil
        case .protection, .adblock:
            return SumiProtectionBundleProfile.unified
        }
    }

    var adblockRuleGroupKinds: Set<AdblockCompiledRuleGroupKind> {
        switch self {
        case .off, .protection:
            return []
        case .adblock:
            return [.network]
        }
    }
}

enum SumiProtectionGroupKind: String, Codable, CaseIterable, Hashable, Sendable {
    case trackingNetwork
    case adblockAdsPrivacyNetwork
    case cosmetic
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
    }

}

struct SumiProtectionNormalTabDecision: Equatable, Sendable {
    let plan: SumiProtectionRulePlan
    let contentBlockingService: SumiContentBlockingService?

    var attachmentState: SumiProtectionAttachmentState {
        plan.attachmentState
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
    let reloadRequiredReason: String?
    let didManualReloadRebuildWebView: Bool
    let appliedAfterManualReload: Bool
    let contentBlockingServiceGenerationId: UInt64?
    let generationSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let requiredBundleProfileId: String?
    let trackingGroupActive: Bool
    let adblockGroupActive: Bool
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
    let planComputeDuration: TimeInterval
    let bundleLookupDuration: TimeInterval?
    let ruleListLookupDuration: TimeInterval?
    let tabAttachmentDuration: TimeInterval?
    let webViewRebuildDuration: TimeInterval?
    let urlHubSummaryDuration: TimeInterval?
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
            "reloadRequiredReason=\(reloadRequiredReason ?? "nil")",
            "manualReloadRebuiltWebView=\(didManualReloadRebuildWebView)",
            "manualReloadMatchedDesiredState=\(appliedAfterManualReload)",
            "contentBlockingServiceGenerationId=\(contentBlockingServiceGenerationId.map(String.init) ?? "nil")",
            "generationSource=\(generationSource?.rawValue ?? "nil")",
            "nativeRuleBundleId=\(nativeRuleBundleId ?? "nil")",
            "bundleProfileId=\(bundleProfileId ?? "nil")",
            "requiredBundleProfileId=\(requiredBundleProfileId ?? "nil")",
            "trackingGroupActive=\(trackingGroupActive)",
            "adblockGroupActive=\(adblockGroupActive)",
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
            "planComputeDuration=\(Self.renderDuration(planComputeDuration))",
            "bundleLookupDuration=\(Self.renderOptionalDuration(bundleLookupDuration))",
            "ruleListLookupDuration=\(Self.renderOptionalDuration(ruleListLookupDuration))",
            "tabAttachmentDuration=\(Self.renderOptionalDuration(tabAttachmentDuration))",
            "webViewRebuildDuration=\(Self.renderOptionalDuration(webViewRebuildDuration))",
            "urlHubSummaryDuration=\(Self.renderOptionalDuration(urlHubSummaryDuration))",
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

    static func renderDuration(_ duration: TimeInterval) -> String {
        String(format: "%.3fms", duration * 1000)
    }

    static func renderOptionalDuration(_ duration: TimeInterval?) -> String {
        duration.map(renderDuration) ?? "nil"
    }
}

struct SumiProtectionGlobalDiagnostics: Equatable, Sendable {
    let selectedProtectionLevel: SumiProtectionLevel
    let appliedProtectionLevel: SumiProtectionLevel
    let browserRestartRequired: Bool
    let generationSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let activeGenerationId: String?
    let remoteReleaseVersion: String?
    let remoteReleaseTag: String?
    let remoteReleaseURL: String?
    let remoteManifestSignatureRequired: Bool
    let remoteManifestSignatureVerified: Bool?
    let remoteSigningKeyId: String?
    let remoteSigningKeyVersion: Int?
    let lastRemoteUpdateError: String?
    let lastSignatureError: String?
    let downgradeRejected: Bool
    let bundleGeneratedDate: Date?
    let lastSuccessfulBundleInstallDate: Date?
    let requiredBundleProfileId: String?
    let preparedBundleAvailable: Bool
    let preparedBundleSource: SumiAdblockBundleInstallSource?
    let searchedBundlePaths: [SumiPreparedAdblockBundleSearchPath]
    let applyNeeded: Bool
    let lastApplySummary: String?
    let lastApplyError: String?
    let globalGroupsAvailable: [SumiProtectionGroupKind]
    let groupSourceDiagnostics: [SumiProtectionGroupKind: String]
    let trackingSourceAvailable: Bool
    let adblockBundleAvailable: Bool
    let strictOffActive: Bool
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
        static let browserRestartRequired = "settings.protection.browserRestartRequired"
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

    @Published private(set) var browserRestartRequired: Bool {
        didSet {
            userDefaults.set(browserRestartRequired, forKey: DefaultsKey.browserRestartRequired)
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
        let rawLevel = userDefaults.string(forKey: DefaultsKey.level)
        let resolvedLevel = rawLevel.flatMap(SumiProtectionLevel.init(rawValue:)) ?? .off
        if rawLevel != resolvedLevel.rawValue {
            userDefaults.set(resolvedLevel.rawValue, forKey: DefaultsKey.level)
        }
        level = resolvedLevel
        browserRestartRequired = userDefaults.bool(forKey: DefaultsKey.browserRestartRequired)

        let rawAppliedLevel = userDefaults.string(forKey: DefaultsKey.appliedLevel)
        let resolvedAppliedLevel = rawAppliedLevel.flatMap(SumiProtectionLevel.init(rawValue:)) ?? resolvedLevel
        appliedLevel = resolvedAppliedLevel
        if rawAppliedLevel != resolvedAppliedLevel.rawValue {
            userDefaults.set(resolvedAppliedLevel.rawValue, forKey: DefaultsKey.appliedLevel)
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

    func setBrowserRestartRequired(_ isRequired: Bool) {
        guard browserRestartRequired != isRequired else { return }
        browserRestartRequired = isRequired
    }
}

@MainActor
final class SumiProtectionCoordinator {
    static let shared = SumiProtectionCoordinator()

    let settings: SumiProtectionSettings
    private let adBlockingModule: SumiAdBlockingModule
    private let siteNormalizer: SumiProtectionSiteNormalizer
    private let bundleRemoteUpdater: any SumiProtectionBundleRemoteUpdating
    let bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore

    private var cancellables = Set<AnyCancellable>()
    private(set) var lastApplySummary: String?
    private(set) var lastApplyError: String?
    private var cachedAttachmentPlan: SumiProtectionGlobalAttachmentPlan?
    private var cachedAttachmentService: SumiContentBlockingService?
    private var contentBlockingServiceGenerationId: UInt64 = 0
    private var runtimeAppliedLevel: SumiProtectionLevel
    private var lastBundleLookupDuration: TimeInterval?
    private var lastPreparedBundleDiscoveryProfileId: String?
    private var lastPreparedBundleDiscovery: SumiPreparedAdblockBundleDiscovery?

    init(
        settings: SumiProtectionSettings = .shared,
        adBlockingModule: SumiAdBlockingModule = .shared,
        siteNormalizer: SumiProtectionSiteNormalizer = SumiProtectionSiteNormalizer(),
        bundleRemoteUpdater: any SumiProtectionBundleRemoteUpdating = SumiProtectionBundleRemoteUpdater(),
        bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore = .shared
    ) {
        self.settings = settings
        self.adBlockingModule = adBlockingModule
        self.siteNormalizer = siteNormalizer
        self.bundleRemoteUpdater = bundleRemoteUpdater
        self.bundleUpdateStatusStore = bundleUpdateStatusStore
        self.runtimeAppliedLevel = settings.appliedLevel
        syncProtectionRuntime(for: runtimeAppliedLevel)
    }

    func setLevel(_ level: SumiProtectionLevel) {
        settings.setLevel(level)
    }

    var applyNeeded: Bool {
        let selectedLevel = settings.level
        guard selectedLevel == settings.appliedLevel else { return true }
        guard !settings.browserRestartRequired else { return false }
        guard let requiredBundleProfileId = selectedLevel.preferredBundleProfileId else {
            return false
        }
        guard activePreparedBundleProfileId == requiredBundleProfileId,
              let manifest = adBlockingModule.activeManifestIfLoaded()
        else { return true }
        let availableGroups = Set(Self.cachedPreparedGroups(level: selectedLevel, manifest: manifest).map(\.group))
        return !Set(selectedLevel.requestedGroups).isSubset(of: availableGroups)
    }

    func applySelectedLevel() async throws -> SumiProtectionApplyOutcome {
        let selectedLevel = settings.level
        let previousAppliedLevel = settings.appliedLevel
        let wasApplyNeeded = applyNeeded
        syncProtectionRuntime(for: selectedLevel)

        do {
            var installedBundleProfileId: String?
            if let requiredBundleProfileId = selectedLevel.preferredBundleProfileId {
                let discoveryStart = Date()
                let discovery = adBlockingModule.preparedNativeRuleBundleDiscovery(
                    profileId: requiredBundleProfileId
                )
                lastBundleLookupDuration = Date().timeIntervalSince(discoveryStart)
                lastPreparedBundleDiscoveryProfileId = requiredBundleProfileId
                lastPreparedBundleDiscovery = discovery
                let shouldInstallDiscoveredRemoteBundle = discovery.resolvedBundle?.source == .remoteReleaseBundle
                    && discovery.resolvedBundle?.bundleId != adBlockingModule.activeManifestIfLoaded()?.nativeRuleBundleId
                if activePreparedBundleProfileId != requiredBundleProfileId || shouldInstallDiscoveredRemoteBundle {
                    guard discovery.resolvedBundle != nil else {
                        throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                            profileId: requiredBundleProfileId,
                            detail: discovery.failureSummary
                        )
                    }
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
                let readinessPlan = globalAttachmentPlan(
                    for: selectedLevel,
                    includeExpensiveDiagnostics: false,
                    loadRuleDefinitions: false
                )
                try validateRequiredGroupsReady(in: readinessPlan)
                installedBundleProfileId = requiredBundleProfileId
            } else {
                clearPreparedBundleLookupDiagnostics()
            }

            settings.setAppliedLevel(selectedLevel)
            if wasApplyNeeded || selectedLevel != previousAppliedLevel {
                settings.setBrowserRestartRequired(true)
            }
            syncProtectionRuntime(for: runtimeAppliedLevel)
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
            syncProtectionRuntime(for: runtimeAppliedLevel)
            let message: String
            if let applyError = error as? SumiProtectionApplyError {
                message = applyError.localizedDescription
            } else {
                message = "Could not apply \(selectedLevel.displayTitle): \(error.localizedDescription)"
            }
            settings.setAppliedLevel(previousAppliedLevel)
            lastApplySummary = nil
            lastApplyError = message
            if selectedLevel == .off {
                clearCachedAttachmentService()
            }
            throw SumiProtectionApplyError.applyFailed(message)
        }
    }

    func updatePreparedBundlesManually() async throws -> SumiProtectionBundleManualUpdateOutcome {
        let profileId = SumiProtectionBundleProfile.adblock
        let appliedLevel = settings.appliedLevel
        syncProtectionRuntime(for: appliedLevel)
        do {
            let remote = try await bundleRemoteUpdater.fetchLatestApprovedBundle(profileId: profileId)
            let activeManifest = adBlockingModule.activeManifestIfLoaded()
            let activation: SumiProtectionBundleManualUpdateActivation
            let restartRequired: Bool
            let summary: String

            if appliedLevel != .off {
                if activeManifest?.nativeRuleBundleId == remote.bundleId
                    || activeManifest?.activeGenerationId == remote.generationId {
                    activation = .alreadyCurrent
                    restartRequired = settings.browserRestartRequired
                    summary = "Prepared bundles are already current: \(remote.releaseVersion)."
                } else {
                    let manifest = try await adBlockingModule.installPreparedNativeRuleBundle(profileId: profileId)
                    guard manifest?.nativeRuleBundleId == remote.bundleId,
                          manifest?.activeGenerationId == remote.generationId
                    else {
                        throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                            profileId: profileId,
                            detail: "The remote bundle was cached but did not become the active prepared bundle."
                        )
                    }
                    try await prepareCachedAttachmentService(for: appliedLevel)
                    settings.setBrowserRestartRequired(true)
                    activation = .installedRestartRequired
                    restartRequired = true
                    summary = "Updated prepared bundles to \(remote.releaseVersion). Restart Sumi or reload open pages before relying on the new rules."
                    lastApplySummary = summary
                    lastApplyError = nil
                }
            } else {
                activation = .cachedOnly
                restartRequired = settings.browserRestartRequired
                summary = "Downloaded prepared bundles \(remote.releaseVersion). They will be used after Protection or Adblock is selected and applied."
            }

            let outcome = SumiProtectionBundleManualUpdateOutcome(
                profileId: profileId,
                releaseVersion: remote.releaseVersion,
                releaseTag: remote.releaseTag,
                bundleId: remote.bundleId,
                generationId: remote.generationId,
                manifestSignatureRequired: remote.manifestSignatureRequired,
                manifestSignatureVerified: remote.manifestSignatureVerified,
                signingKeyId: remote.signingKeyId,
                signingKeyVersion: remote.signingKeyVersion,
                activation: activation,
                browserRestartRequired: restartRequired,
                summary: summary
            )
            bundleUpdateStatusStore.recordSuccess(outcome)
            return outcome
        } catch {
            bundleUpdateStatusStore.recordFailure(error)
            throw error
        }
    }

    @discardableResult
    func restoreAppliedLevelForStartup() async throws -> AdblockCompiledGenerationManifest? {
        let appliedLevel = settings.appliedLevel
#if DEBUG
        let startupDiagnosticsToken = SumiProtectionStartupRestoreDiagnostics.shared.begin(appliedLevel: appliedLevel)
        defer {
            let snapshot = SumiProtectionStartupRestoreDiagnostics.shared.finish(startupDiagnosticsToken)
            Logger.sumi(category: "ProtectionStartupRestore").debug("\(snapshot.developerReport, privacy: .public)")
        }
#endif
        runtimeAppliedLevel = appliedLevel
        syncProtectionRuntime(for: appliedLevel)
        guard let requiredBundleProfileId = appliedLevel.preferredBundleProfileId else {
            clearPreparedBundleLookupDiagnostics()
            try await prepareCachedAttachmentService(for: appliedLevel)
            settings.setBrowserRestartRequired(false)
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
            try await prepareCachedAttachmentService(for: appliedLevel)
            settings.setBrowserRestartRequired(false)
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

    func normalTabDecision(
        for url: URL?,
        profileId: UUID?
    ) -> SumiProtectionNormalTabDecision {
        let plan = cachedRulePlan(for: url, profileId: profileId)
        return SumiProtectionNormalTabDecision(
            plan: plan,
            contentBlockingService: cachedContentBlockingService(for: plan)
        )
    }

    func desiredAttachmentState(for url: URL?) -> SumiProtectionAttachmentState {
        cachedRulePlan(for: url, profileId: nil).attachmentState
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
        let requestedLevel = runtimeAppliedLevel
        let manifest = requestedLevel == .off
            ? nil
            : adBlockingModule.activeManifestIfLoaded()
        let eligibility = SumiAdblockSurfaceEligibility.evaluate(
            url: url,
            normalizer: siteNormalizer
        )
        let siteHost = eligibility.normalizedSiteHost
        let shouldConsultSiteOverride = requestedLevel != .off && eligibility.isEligible
        let siteOverride = shouldConsultSiteOverride
            ? adBlockingModule.siteOverride(for: url)
            : .inherit
        let siteAllowsProtection = requestedLevel != .off
            && eligibility.isEligible
            && siteOverride != .disabled

        let globalPlan = siteAllowsProtection
            ? globalAttachmentPlan(
                for: requestedLevel,
                includeExpensiveDiagnostics: includeExpensiveDiagnostics,
                loadRuleDefinitions: loadRuleDefinitions
            )
            : emptyGlobalAttachmentPlan(
                for: requestedLevel,
                manifest: manifest
            )

        let requestedGroups = siteAllowsProtection ? requestedLevel.requestedGroups : []
        let inactiveGroups = requestedGroups
            .filter { !globalPlan.activeGroups.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        let effectiveLevel = Self.effectiveLevel(for: globalPlan.activeGroups)

        return SumiProtectionRulePlan(
            requestedLevel: requestedLevel,
            effectiveLevel: effectiveLevel,
            siteHost: siteHost,
            siteOverride: siteOverride,
            sitePolicyAllowsProtection: siteAllowsProtection,
            activeGroups: globalPlan.activeGroups,
            inactiveGroups: inactiveGroups,
            bundleSource: globalPlan.bundleSource,
            nativeRuleBundleId: globalPlan.nativeRuleBundleId,
            bundleProfileId: globalPlan.bundleProfileId,
            requiredBundleProfileId: globalPlan.requiredBundleProfileId,
            activeGenerationId: globalPlan.activeGenerationId,
            previousGenerationId: globalPlan.previousGenerationId,
            previousGenerationRetained: globalPlan.previousGenerationRetained,
            ruleCountsByGroup: globalPlan.ruleCountsByGroup,
            shardCountsByGroup: globalPlan.shardCountsByGroup,
            expectedRuleListIdentifiers: globalPlan.expectedRuleListIdentifiers,
            dedupeSummary: globalPlan.dedupeSummary,
            overlapSummary: globalPlan.overlapSummary,
            ineligibleSurfaceReason: eligibility.ineligibleReason,
            planningErrors: globalPlan.planningErrors,
            ruleDefinitions: globalPlan.ruleDefinitions
        )
    }

    private func globalAttachmentPlan(
        for level: SumiProtectionLevel,
        includeExpensiveDiagnostics: Bool,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionGlobalAttachmentPlan {
        let manifest = adBlockingModule.activeManifestIfLoaded()
        if !loadRuleDefinitions,
           !includeExpensiveDiagnostics,
           let cachedAttachmentPlan,
           cachedAttachmentPlanMatches(cachedAttachmentPlan, level: level, manifest: manifest)
        {
            return metadataOnlyGlobalAttachmentPlan(cachedAttachmentPlan)
        }

        var activeGroups = [SumiProtectionGroupKind]()
        var ruleCountsByGroup = [SumiProtectionGroupKind: Int]()
        var shardCountsByGroup = [SumiProtectionGroupKind: Int]()
        var expectedRuleListIdentifiers = [String]()
        var plannedDefinitions = [PlannedRuleDefinition]()
        var planningErrors = [String]()
        let preparedBundleProfileId = manifest.flatMap { Self.preparedBundleProfileId(in: $0) }

        if let requiredProfileId = level.preferredBundleProfileId {
            if preparedBundleProfileId == requiredProfileId {
                if loadRuleDefinitions {
                    do {
                        let definitions = try adBlockingModule.contentRuleListDefinitions(
                            for: Set(level.requestedGroups)
                        )
                        let grouped = groupPreparedDefinitions(
                            definitions,
                            level: level,
                            manifest: manifest
                        )
                        for entry in grouped where !entry.definitions.isEmpty {
                            activeGroups.append(entry.group)
                            ruleCountsByGroup[entry.group] = entry.ruleCount
                            shardCountsByGroup[entry.group] = entry.definitions.count
                            plannedDefinitions.append(contentsOf: entry.definitions.map {
                                PlannedRuleDefinition(
                                    group: entry.group,
                                    source: entry.group == .trackingNetwork ? .tracking : .adblock,
                                    definition: $0
                                )
                            })
                        }
                    } catch {
                        planningErrors.append("Prepared protection bundle rules unavailable: \(error.localizedDescription)")
                    }
                } else if let manifest {
                    let grouped = Self.cachedPreparedGroups(
                        level: level,
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
            let availablePreparedGroups = manifest.map {
                Set(Self.cachedPreparedGroups(level: level, manifest: $0).map(\.group))
            } ?? []
            for group in level.requestedGroups where !availablePreparedGroups.contains(group) {
                planningErrors.append("Prepared \(group.rawValue) group is unavailable in active bundle.")
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
            expectedRuleListIdentifiers = deduped.definitions.map(\.definition.webKitStoreIdentifier).sorted()
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

        return SumiProtectionGlobalAttachmentPlan(
            level: level,
            activeGroups: finalActiveGroups,
            inactiveGroups: level.requestedGroups.filter { !finalActiveGroups.contains($0) },
            ruleCountsByGroup: ruleCountsByGroup,
            shardCountsByGroup: shardCountsByGroup,
            expectedRuleListIdentifiers: expectedRuleListIdentifiers,
            dedupeSummary: dedupeSummary,
            overlapSummary: overlapSummary,
            planningErrors: planningErrors,
            ruleDefinitions: ruleDefinitions,
            bundleSource: manifest?.generationSource,
            nativeRuleBundleId: manifest?.nativeRuleBundleId,
            bundleProfileId: Self.installedBundleProfileId(from: manifest),
            requiredBundleProfileId: level.preferredBundleProfileId,
            activeGenerationId: manifest?.activeGenerationId,
            previousGenerationId: manifest?.previousGenerationId,
            previousGenerationRetained: manifest?.previousGenerationId != nil
        )
    }

    private func emptyGlobalAttachmentPlan(
        for level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> SumiProtectionGlobalAttachmentPlan {
        SumiProtectionGlobalAttachmentPlan(
            level: level,
            activeGroups: [],
            inactiveGroups: [],
            ruleCountsByGroup: [:],
            shardCountsByGroup: [:],
            expectedRuleListIdentifiers: [],
            dedupeSummary: .empty,
            overlapSummary: .deferred,
            planningErrors: [],
            ruleDefinitions: [],
            bundleSource: manifest?.generationSource,
            nativeRuleBundleId: manifest?.nativeRuleBundleId,
            bundleProfileId: Self.installedBundleProfileId(from: manifest),
            requiredBundleProfileId: level.preferredBundleProfileId,
            activeGenerationId: manifest?.activeGenerationId,
            previousGenerationId: manifest?.previousGenerationId,
            previousGenerationRetained: manifest?.previousGenerationId != nil
        )
    }

    private func metadataOnlyGlobalAttachmentPlan(
        _ plan: SumiProtectionGlobalAttachmentPlan
    ) -> SumiProtectionGlobalAttachmentPlan {
        SumiProtectionGlobalAttachmentPlan(
            level: plan.level,
            activeGroups: plan.activeGroups,
            inactiveGroups: plan.inactiveGroups,
            ruleCountsByGroup: plan.ruleCountsByGroup,
            shardCountsByGroup: plan.shardCountsByGroup,
            expectedRuleListIdentifiers: plan.expectedRuleListIdentifiers,
            dedupeSummary: plan.dedupeSummary,
            overlapSummary: .deferred,
            planningErrors: plan.planningErrors,
            ruleDefinitions: [],
            bundleSource: plan.bundleSource,
            nativeRuleBundleId: plan.nativeRuleBundleId,
            bundleProfileId: plan.bundleProfileId,
            requiredBundleProfileId: plan.requiredBundleProfileId,
            activeGenerationId: plan.activeGenerationId,
            previousGenerationId: plan.previousGenerationId,
            previousGenerationRetained: plan.previousGenerationRetained
        )
    }

    private func cachedAttachmentPlanMatches(
        _ plan: SumiProtectionGlobalAttachmentPlan,
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> Bool {
        guard plan.level == level else { return false }
        guard plan.requiredBundleProfileId == level.preferredBundleProfileId else { return false }
        guard plan.activeGenerationId == manifest?.activeGenerationId else { return false }
        guard plan.bundleProfileId == Self.installedBundleProfileId(from: manifest) else { return false }
        return true
    }

    private func cachedContentBlockingService(
        for plan: SumiProtectionRulePlan
    ) -> SumiContentBlockingService? {
        guard plan.sitePolicyAllowsProtection,
              !plan.expectedRuleListIdentifiers.isEmpty,
              let cachedAttachmentPlan,
              let cachedAttachmentService,
              cachedAttachmentPlanMatches(
                cachedAttachmentPlan,
                level: plan.requestedLevel,
                manifest: adBlockingModule.activeManifestIfLoaded()
              ),
              cachedAttachmentService.latestRuleListIdentifiers == plan.expectedRuleListIdentifiers
        else { return nil }
        return cachedAttachmentService
    }

    private func prepareCachedAttachmentService(
        for level: SumiProtectionLevel
    ) async throws {
        guard level != .off else {
            clearCachedAttachmentService()
            return
        }

        let metadataPlan = globalAttachmentPlan(
            for: level,
            includeExpensiveDiagnostics: false,
            loadRuleDefinitions: false
        )
#if DEBUG
        SumiProtectionStartupRestoreDiagnostics.shared.recordExpectedShardIdentifiers(
            metadataPlan.expectedRuleListIdentifiers
        )
#endif

        try validateRequiredGroupsReady(in: metadataPlan)

        guard metadataPlan.isAttachable else {
            clearCachedAttachmentService()
            cachedAttachmentPlan = metadataOnlyGlobalAttachmentPlan(metadataPlan)
            return
        }

        let service = SumiContentBlockingService(policy: .disabled)

        let metadataOnlyDefinitions = metadataOnlyRuleDefinitions(
            matching: metadataPlan.expectedRuleListIdentifiers,
            manifest: adBlockingModule.activeManifestIfLoaded()
        )
        if metadataOnlyDefinitions.map(\.webKitStoreIdentifier).sorted()
            == metadataPlan.expectedRuleListIdentifiers.sorted()
        {
            do {
                let preparedUpdate = try await service.prepareExistingRuleListUpdate(
                    ruleLists: metadataOnlyDefinitions
                )
                service.commitPreparedContentBlockingUpdate(preparedUpdate)
                cachedAttachmentPlan = metadataOnlyGlobalAttachmentPlan(metadataPlan)
                cachedAttachmentService = service
                contentBlockingServiceGenerationId &+= 1
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordMetadataOnlyRestoreUsed()
#endif
                return
            } catch {
#if DEBUG
                let fallbackReason = "Protection attachment lookup-only restore failed: \(error.localizedDescription)"
                SumiProtectionStartupRestoreDiagnostics.shared.recordFallback(reason: fallbackReason)
                SumiProtectionStartupRestoreDiagnostics.shared.recordPayloadBackedRestoreUsed(reason: fallbackReason)
                SumiProtectionStartupRestoreDiagnostics.shared.recordRepairCompileUsed(reason: fallbackReason)
#endif
                // Repair-on-miss stays on the existing payload-backed path below.
            }
        }

        let plan = globalAttachmentPlan(
            for: level,
            includeExpensiveDiagnostics: false,
            loadRuleDefinitions: true
        )
        try validateRequiredGroupsReady(in: plan)

        guard plan.isAttachable else {
            clearCachedAttachmentService()
            cachedAttachmentPlan = metadataOnlyGlobalAttachmentPlan(plan)
            return
        }

        let preparedUpdate = try await service.prepareRuleListUpdate(
            ruleLists: plan.ruleDefinitions,
            retainEncodedRuleListsInPreparedPolicy: false
        )
        service.commitPreparedContentBlockingUpdate(preparedUpdate)
        cachedAttachmentPlan = metadataOnlyGlobalAttachmentPlan(plan)
        cachedAttachmentService = service
        contentBlockingServiceGenerationId &+= 1
    }

    private func metadataOnlyRuleDefinitions(
        matching identifiers: [String],
        manifest: AdblockCompiledGenerationManifest?
    ) -> [SumiContentRuleListDefinition] {
        guard let manifest else { return [] }
        let expectedIdentifiers = Set(identifiers)
        return manifest.networkShards
            .filter { expectedIdentifiers.contains($0.webKitIdentifier) }
            .sorted { lhs, rhs in
                lhs.kind == rhs.kind
                    ? lhs.id < rhs.id
                    : lhs.kind.rawValue < rhs.kind.rawValue
            }
            .map { shard in
                SumiContentRuleListDefinition(
                    name: shard.webKitIdentifier,
                    encodedContentRuleList: "",
                    storeIdentifierOverride: shard.webKitIdentifier,
                    contentHashOverride: shard.contentHash
                )
            }
    }

    private func validateRequiredGroupsReady(
        in plan: SumiProtectionGlobalAttachmentPlan
    ) throws {
        if let requiredProfileId = plan.requiredBundleProfileId,
           plan.bundleProfileId != requiredProfileId
        {
            throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                profileId: requiredProfileId,
                detail: "The active prepared bundle after install is \(plan.bundleProfileId ?? "nil")."
            )
        }

        switch plan.level {
        case .off:
            return
        case .protection:
            guard plan.activeGroups.contains(.trackingNetwork) else {
                throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                    profileId: SumiProtectionBundleProfile.unified,
                    detail: "No prepared trackingNetwork rule lists were available after install."
                )
            }
        case .adblock:
            guard plan.activeGroups.contains(.trackingNetwork) else {
                throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                    profileId: SumiProtectionBundleProfile.unified,
                    detail: "No prepared trackingNetwork rule lists were available after install."
                )
            }
            guard plan.activeGroups.contains(.adblockAdsPrivacyNetwork) else {
                throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                    profileId: SumiProtectionBundleProfile.adblock,
                    detail: "No adguardAdsPrivacy network rule lists were available after install."
                )
            }
        }
    }

    private func clearCachedAttachmentService() {
        cachedAttachmentPlan = nil
        cachedAttachmentService = nil
        contentBlockingServiceGenerationId &+= 1
    }

    private func clearPreparedBundleLookupDiagnostics() {
        lastBundleLookupDuration = nil
        lastPreparedBundleDiscoveryProfileId = nil
        lastPreparedBundleDiscovery = nil
    }

    func currentTabDiagnostics(
        for url: URL?,
        appliedState: SumiProtectionAttachmentState?,
        reloadRequired: Bool,
        reloadRequiredReason: String? = nil,
        didManualReloadRebuildWebView: Bool = false,
        appliedAfterManualReload: Bool = false,
        actualAttachedRuleListIdentifiers: [String]? = nil,
        contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary? = nil,
        webViewRebuildDuration: TimeInterval? = nil,
        urlHubSummaryDuration: TimeInterval? = nil
    ) -> SumiProtectionCurrentTabDiagnostics {
        let planStart = Date()
        let plan = rulePlan(
            for: url,
            profileId: nil,
            includeExpensiveDiagnostics: true
        )
        let planComputeDuration = Date().timeIntervalSince(planStart)
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
        let unexpected = actual.filter {
            !expectedSet.contains($0) && Self.isSumiOwnedProtectionIdentifier($0)
        }

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
            reloadRequiredReason: reloadRequired ? (reloadRequiredReason ?? "protection attachment plan changed") : nil,
            didManualReloadRebuildWebView: didManualReloadRebuildWebView,
            appliedAfterManualReload: appliedAfterManualReload,
            contentBlockingServiceGenerationId: contentBlockingServiceGenerationId,
            generationSource: plan.bundleSource,
            nativeRuleBundleId: plan.nativeRuleBundleId,
            bundleProfileId: plan.bundleProfileId,
            requiredBundleProfileId: plan.requiredBundleProfileId,
            trackingGroupActive: plan.trackingGroupActive,
            adblockGroupActive: plan.adblockGroupActive,
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
            planComputeDuration: planComputeDuration,
            bundleLookupDuration: lastBundleLookupDuration,
            ruleListLookupDuration: contentBlockingAssetSummary?.ruleListLookupDuration,
            tabAttachmentDuration: contentBlockingAssetSummary?.tabAttachmentDuration,
            webViewRebuildDuration: webViewRebuildDuration,
            urlHubSummaryDuration: urlHubSummaryDuration,
            planningErrors: plan.planningErrors
        )
    }

    func globalDiagnostics() -> SumiProtectionGlobalDiagnostics {
        let selectedLevel = settings.level
        let appliedLevel = settings.appliedLevel
        let manifest = selectedLevel == .off && appliedLevel == .off
            ? nil
            : adBlockingModule.activeManifestIfLoaded()
        let installedBundleProfileId = Self.installedBundleProfileId(from: manifest)
        let activePreparedProfileId = manifest.flatMap { Self.preparedBundleProfileId(in: $0) }
        let requiredBundleProfileId = selectedLevel.preferredBundleProfileId
        let preparedBundleDiscovery = requiredBundleProfileId == lastPreparedBundleDiscoveryProfileId
            ? lastPreparedBundleDiscovery
            : nil
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
            browserRestartRequired: settings.browserRestartRequired,
            generationSource: manifest?.generationSource,
            nativeRuleBundleId: manifest?.nativeRuleBundleId,
            bundleProfileId: installedBundleProfileId,
            activeGenerationId: manifest?.activeGenerationId,
            remoteReleaseVersion: manifest?.remoteReleaseVersion,
            remoteReleaseTag: manifest?.remoteReleaseTag,
            remoteReleaseURL: manifest?.remoteReleaseURL,
            remoteManifestSignatureRequired: SumiProtectionBundleTrust.remoteManifestSignatureRequired,
            remoteManifestSignatureVerified: manifest?.remoteManifestSignatureVerified
                ?? bundleUpdateStatusStore.lastSignatureVerified,
            remoteSigningKeyId: manifest?.remoteSigningKeyId
                ?? bundleUpdateStatusStore.lastSigningKeyId,
            remoteSigningKeyVersion: manifest?.remoteSigningKeyVersion
                ?? bundleUpdateStatusStore.lastSigningKeyVersion,
            lastRemoteUpdateError: bundleUpdateStatusStore.lastFailureReason,
            lastSignatureError: bundleUpdateStatusStore.lastSignatureError,
            downgradeRejected: bundleUpdateStatusStore.lastDowngradeRejected ?? false,
            bundleGeneratedDate: manifest?.createdDate,
            lastSuccessfulBundleInstallDate: manifest?.lastSuccessfulUpdateDate,
            requiredBundleProfileId: requiredBundleProfileId,
            preparedBundleAvailable: preparedBundleDiscovery?.isAvailable ?? (requiredBundleProfileId.map { activePreparedProfileId == $0 } ?? true),
            preparedBundleSource: preparedBundleDiscovery?.source ?? (
                requiredBundleProfileId != nil && activePreparedProfileId == requiredBundleProfileId
                    ? manifest?.generationSource.sumiBundleInstallSource
                    : nil
            ),
            searchedBundlePaths: preparedBundleDiscovery?.searchedPaths ?? [],
            applyNeeded: applyNeeded,
            lastApplySummary: lastApplySummary,
            lastApplyError: lastApplyError,
            globalGroupsAvailable: availableGroups,
            groupSourceDiagnostics: Self.groupSourceDiagnostics(from: manifest),
            trackingSourceAvailable: trackingSourceAvailable,
            adblockBundleAvailable: adblockBundleAvailable,
            strictOffActive: selectedLevel == .off
                && appliedLevel == .off
                && cachedAttachmentPlan == nil
                && cachedAttachmentService == nil
                && !adBlockingModule.isEnabled
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
        let unexpectedOldIdentifiers = currentTabDiagnostics?.unexpectedOldRuleListIdentifiers ?? []
        let reloadRequired = currentTabDiagnostics?.reloadRequired ?? false
        let reloadRequiredReason = currentTabDiagnostics?.reloadRequiredReason
        let didManualReloadRebuildWebView = currentTabDiagnostics?.didManualReloadRebuildWebView ?? false
        let appliedAfterManualReload = currentTabDiagnostics?.appliedAfterManualReload ?? false
        var lines = [
            "Sumi Adblock & Protection Copy Diagnostics",
            "timestamp=\(Self.iso8601Timestamp(Date()))",
            "",
            "Global protection state",
            "protectionLevel=\(global.selectedProtectionLevel.rawValue)",
            "appliedProtectionLevel=\(global.appliedProtectionLevel.rawValue)",
            "restartRequired=\(global.browserRestartRequired)",
            "browserRestartRequired=\(global.browserRestartRequired)",
            "generationSource=\(global.generationSource?.rawValue ?? "nil")",
            "nativeRuleBundleId=\(global.nativeRuleBundleId ?? "nil")",
            "bundleProfileId=\(global.bundleProfileId ?? "nil")",
            "activeGenerationId=\(global.activeGenerationId ?? "nil")",
            "remoteReleaseVersion=\(global.remoteReleaseVersion ?? "nil")",
            "remoteManifestSignatureRequired=\(global.remoteManifestSignatureRequired)",
            "remoteManifestSignatureVerified=\(global.remoteManifestSignatureVerified.map(String.init) ?? "nil")",
            "signingKeyId=\(global.remoteSigningKeyId ?? "nil")",
            "signingKeyVersion=\(global.remoteSigningKeyVersion.map(String.init) ?? "nil")",
            "lastRemoteUpdateError=\(global.lastRemoteUpdateError ?? "nil")",
            "lastSignatureError=\(global.lastSignatureError ?? "nil")",
            "downgradeRejected=\(global.downgradeRejected)",
            "requiredBundleProfileId=\(global.requiredBundleProfileId ?? "nil")",
            "preparedBundleAvailable=\(global.preparedBundleAvailable)",
            "preparedBundleSource=\(global.preparedBundleSource?.rawValue ?? "nil")",
            "searchedBundlePaths=\(Self.renderSearchedBundlePaths(global.searchedBundlePaths))",
            "applyNeeded=\(global.applyNeeded)",
            "lastApplySummary=\(global.lastApplySummary ?? "nil")",
            "lastApplyError=\(global.lastApplyError ?? "nil")",
            "globalGroupsAvailable=\(global.globalGroupsAvailable.map(\.rawValue).joined(separator: ","))",
            "trackingNetworkSourceLicenseSummary=\(global.groupSourceDiagnostics[.trackingNetwork] ?? "nil")",
            "adblockAdsPrivacyNetworkSourceSummary=\(global.groupSourceDiagnostics[.adblockAdsPrivacyNetwork] ?? "nil")",
            "trackingSourceAvailable=\(global.trackingSourceAvailable)",
            "adblockBundleAvailable=\(global.adblockBundleAvailable)",
            "strictOffActive=\(global.strictOffActive)",
            "",
            "Target page plan",
            "targetSource=\(targetDescription)",
            "targetURL=\(targetURLString)",
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
            "ruleCountsByGroup=\(SumiProtectionCurrentTabDiagnostics.renderCounts(plan.ruleCountsByGroup))",
            "shardCountsByGroup=\(SumiProtectionCurrentTabDiagnostics.renderCounts(plan.shardCountsByGroup))",
            "expectedRuleListIdentifiers=\(plan.expectedRuleListIdentifiers.joined(separator: ","))",
            "lookupSucceededIdentifiers=\(lookupSucceededIdentifiers.joined(separator: ","))",
            "lookupFailedIdentifiers=\(lookupFailedIdentifiers.joined(separator: ","))",
            "addedToUserContentControllerIdentifiers=\(addedIdentifiers.joined(separator: ","))",
            "actualAttachedRuleListIdentifiers=\(actualAttachedIdentifiers.joined(separator: ","))",
            "missingIdentifiers=\(missingIdentifiers.joined(separator: ","))",
            "missingAfterAttachmentIdentifiers=\(missingIdentifiers.joined(separator: ","))",
            "unexpectedOldIdentifiers=\(unexpectedOldIdentifiers.joined(separator: ","))",
            "ruleListIdentifierSamplesByGroup=\(SumiProtectionCurrentTabDiagnostics.renderIdentifierSamples(Self.ruleListIdentifierSamplesByGroup(for: plan)))",
            "reloadRequired=\(reloadRequired)",
            "reloadRequiredReason=\(reloadRequiredReason ?? "nil")",
            "manualReloadRebuiltWebView=\(didManualReloadRebuildWebView)",
            "manualReloadMatchedDesiredState=\(appliedAfterManualReload)",
            "contentBlockingServiceGenerationId=\(contentBlockingServiceGenerationId)",
            "planComputeDuration=\(currentTabDiagnostics.map { SumiProtectionCurrentTabDiagnostics.renderDuration($0.planComputeDuration) } ?? "nil")",
            "bundleLookupDuration=\(SumiProtectionCurrentTabDiagnostics.renderOptionalDuration(lastBundleLookupDuration))",
            "ruleListLookupDuration=\(SumiProtectionCurrentTabDiagnostics.renderOptionalDuration(currentTabDiagnostics?.ruleListLookupDuration))",
            "tabAttachmentDuration=\(SumiProtectionCurrentTabDiagnostics.renderOptionalDuration(currentTabDiagnostics?.tabAttachmentDuration))",
            "webViewRebuildDuration=\(SumiProtectionCurrentTabDiagnostics.renderOptionalDuration(currentTabDiagnostics?.webViewRebuildDuration))",
            "urlHubSummaryDuration=\(SumiProtectionCurrentTabDiagnostics.renderOptionalDuration(currentTabDiagnostics?.urlHubSummaryDuration))",
            "dedupeSummary=\(plan.dedupeSummary.reportLine)",
            "overlapSummary=\(plan.overlapSummary.reportLine)",
            "planningErrors=\(plan.planningErrors.joined(separator: " | "))",
            "currentTabDiagnosticsAvailable=\(currentTabDiagnostics != nil)",
        ]
#if DEBUG
        if let startupSnapshot = SumiProtectionStartupRestoreDiagnostics.shared.latestSnapshot {
            lines.append("")
            lines.append("Startup restore diagnostics")
            lines.append(contentsOf: startupSnapshot.reportLines)
        }
#endif
        if currentTabDiagnostics == nil {
            lines.append("Sumi Adblock & Protection current-tab diagnostics\ncurrentTab=nil")
        }
        return lines.joined(separator: "\n")
    }
#endif

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

    private func syncProtectionRuntime(for level: SumiProtectionLevel) {
        switch level {
        case .off:
            adBlockingModule.setEnabled(false)
            adBlockingModule.setPreparedBundleRuntimeEnabled(false)
        case .protection:
            adBlockingModule.setPreparedBundleRuntimeEnabled(true)
            adBlockingModule.setEnabled(false)
        case .adblock:
            adBlockingModule.setPreparedBundleRuntimeEnabled(true)
            adBlockingModule.setEnabled(true)
        }
    }

    private func applySummary(
        selectedLevel: SumiProtectionLevel,
        installedBundleProfileId: String?
    ) -> String {
        if let installedBundleProfileId {
            return "Saved \(selectedLevel.displayTitle) using prepared bundle \(installedBundleProfileId). Restart Sumi to apply global protection changes."
        }
        return "Saved \(selectedLevel.displayTitle). Restart Sumi to apply global protection changes."
    }

    private func cachedTrackingSourceAvailable() -> Bool {
        guard let manifest = adBlockingModule.activeManifestIfLoaded() else { return false }
        return Self.cachedPreparedGroups(level: .protection, manifest: manifest)
            .contains { $0.group == .trackingNetwork && $0.shardCount > 0 }
    }

    private static func groupSourceDiagnostics(
        from manifest: AdblockCompiledGenerationManifest?
    ) -> [SumiProtectionGroupKind: String] {
        guard let manifest else { return [:] }
        return (manifest.nativeLogicalGroups ?? []).reduce(into: [:]) { result, group in
            result[group.id] = group.reportLine
        }
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
            groups.append(contentsOf: Self.cachedPreparedGroups(level: .adblock, manifest: manifest).map(\.group))
        }

        return groups.uniqueSorted()
    }

    private func groupPreparedDefinitions(
        _ definitions: [SumiContentRuleListDefinition],
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> [(group: SumiProtectionGroupKind, definitions: [SumiContentRuleListDefinition], ruleCount: Int)] {
        guard let manifest,
              Self.preparedBundleProfileId(in: manifest) != nil
        else { return [] }
        let definitionsByIdentifier = definitions.reduce(into: [String: SumiContentRuleListDefinition]()) { result, definition in
            result[definition.webKitStoreIdentifier] = definition
        }
        return Self.cachedPreparedGroups(level: level, manifest: manifest)
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

    private static func cachedPreparedGroups(
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest
    ) -> [CachedAdblockGroup] {
        guard let bundleProfileId = preparedBundleProfileId(in: manifest) else { return [] }
        let groups = manifest.allNativeShards.reduce(into: [SumiProtectionGroupKind: CachedAdblockGroup]()) { result, shard in
            guard let group = protectionGroup(
                for: shard,
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
        for shard: NativeContentBlockingShardDescriptor,
        bundleProfileId: String,
        level: SumiProtectionLevel
    ) -> SumiProtectionGroupKind? {
        guard shard.kind == .network else { return nil }
        if let protectionGroup = shard.protectionGroup {
            return level.requestedGroups.contains(protectionGroup) ? protectionGroup : nil
        }
        switch (bundleProfileId, level) {
        case (SumiProtectionBundleProfile.adblock, .adblock):
            return .adblockAdsPrivacyNetwork
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
        return inferredBundleProfileId(from: manifest.nativeRuleBundleId)
    }

    private static func inferredBundleProfileId(from nativeRuleBundleId: String?) -> String? {
        guard let nativeRuleBundleId else { return nil }
        for profileId in [SumiProtectionBundleProfile.adblock] {
            if nativeRuleBundleId.contains(profileId) {
                return profileId
            }
        }
        return nil
    }

    private static func effectiveLevel(
        for activeGroups: [SumiProtectionGroupKind]
    ) -> SumiProtectionLevel {
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
            let identifier = planned.definition.webKitStoreIdentifier
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
            case .adblockAdsPrivacyNetwork:
                identifiers = plan.expectedRuleListIdentifiers.filter {
                    $0.hasPrefix("sumi.adblock.network.")
                }
            case .cosmetic:
                identifiers = []
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

    private static func isSumiOwnedProtectionIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("sumi.adblock.")
            || identifier.hasPrefix("sumi.tracking.")
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

private struct SumiProtectionGlobalAttachmentPlan: Equatable, Sendable {
    let level: SumiProtectionLevel
    let activeGroups: [SumiProtectionGroupKind]
    let inactiveGroups: [SumiProtectionGroupKind]
    let ruleCountsByGroup: [SumiProtectionGroupKind: Int]
    let shardCountsByGroup: [SumiProtectionGroupKind: Int]
    let expectedRuleListIdentifiers: [String]
    let dedupeSummary: SumiProtectionDedupeSummary
    let overlapSummary: SumiProtectionOverlapSummary
    let planningErrors: [String]
    let ruleDefinitions: [SumiContentRuleListDefinition]
    let bundleSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let requiredBundleProfileId: String?
    let activeGenerationId: String?
    let previousGenerationId: String?
    let previousGenerationRetained: Bool

    var isAttachable: Bool {
        !activeGroups.isEmpty && !expectedRuleListIdentifiers.isEmpty
    }
}

private struct CachedAdblockGroup: Equatable, Sendable {
    let group: SumiProtectionGroupKind
    let identifiers: [String]
    let shardCount: Int
    let ruleCount: Int
}

private extension AdblockRuleGenerationSource {
    var isPreparedBundleSource: Bool {
        true
    }

    var sumiBundleInstallSource: SumiAdblockBundleInstallSource? {
        switch self {
        case .embeddedBundle:
            return .appResource
        case .developmentBundle:
            return .developmentBundle
        case .remoteReleaseBundle:
            return .remoteReleaseBundle
        }
    }
}

private extension Array where Element == SumiProtectionGroupKind {
    func uniqueSorted() -> [SumiProtectionGroupKind] {
        Array(Set(self)).sorted { $0.rawValue < $1.rawValue }
    }
}
