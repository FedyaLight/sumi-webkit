import Combine
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
    private let attachmentOwner: SumiProtectionAttachmentOwner
    private let bundleLifecycle: SumiProtectionBundleLifecycle

    var bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore {
        bundleLifecycle.statusStore
    }

    private(set) var lastApplySummary: String?
    private(set) var lastApplyError: String?
    private var runtimeAppliedLevel: SumiProtectionLevel

    init(
        settings: SumiProtectionSettings = .shared,
        adBlockingModule: SumiAdBlockingModule = .shared,
        siteNormalizer: SumiProtectionSiteNormalizer = SumiProtectionSiteNormalizer(),
        bundleRemoteUpdater: any SumiProtectionBundleRemoteUpdating = SumiProtectionBundleRemoteUpdater(),
        bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore = .shared
    ) {
        self.settings = settings
        self.adBlockingModule = adBlockingModule
        self.attachmentOwner = SumiProtectionAttachmentOwner(
            ruleProvider: adBlockingModule,
            siteNormalizer: siteNormalizer
        )
        self.bundleLifecycle = SumiProtectionBundleLifecycle(
            preparedBundleManager: adBlockingModule,
            remoteUpdater: bundleRemoteUpdater,
            statusStore: bundleUpdateStatusStore
        )
        self.runtimeAppliedLevel = settings.appliedLevel
        attachmentOwner.syncRuntime(for: runtimeAppliedLevel)
    }

    func setLevel(_ level: SumiProtectionLevel) {
        settings.setLevel(level)
    }

    var applyNeeded: Bool {
        attachmentOwner.applyNeeded(
            selectedLevel: settings.level,
            appliedLevel: settings.appliedLevel,
            browserRestartRequired: settings.browserRestartRequired
        )
    }

    func applySelectedLevel() async throws -> SumiProtectionApplyOutcome {
        let selectedLevel = settings.level
        let previousAppliedLevel = settings.appliedLevel
        let wasApplyNeeded = applyNeeded
        attachmentOwner.syncRuntime(for: selectedLevel)

        do {
            var installedBundleProfileId: String?
            if let requiredBundleProfileId = selectedLevel.preferredBundleProfileId {
                installedBundleProfileId = try await bundleLifecycle.ensurePreparedBundleInstalled(
                    profileId: requiredBundleProfileId
                )
                let readinessPlan = attachmentOwner.globalAttachmentPlan(
                    for: selectedLevel,
                    includeExpensiveDiagnostics: false,
                    loadRuleDefinitions: false
                )
                try attachmentOwner.validateRequiredGroupsReady(in: readinessPlan)
            } else {
                clearPreparedBundleLookupDiagnostics()
            }

            settings.setAppliedLevel(selectedLevel)
            if wasApplyNeeded || selectedLevel != previousAppliedLevel {
                settings.setBrowserRestartRequired(true)
            }
            runtimeAppliedLevel = selectedLevel
            attachmentOwner.syncRuntime(for: runtimeAppliedLevel)
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
            attachmentOwner.syncRuntime(for: runtimeAppliedLevel)
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
                attachmentOwner.clearCachedAttachmentService()
            }
            throw SumiProtectionApplyError.applyFailed(message)
        }
    }

    func updatePreparedBundlesManually() async throws -> SumiProtectionBundleManualUpdateOutcome {
        let appliedLevel = settings.appliedLevel
        attachmentOwner.syncRuntime(for: appliedLevel)
        return try await bundleLifecycle.updatePreparedBundlesManually(
            appliedLevel: appliedLevel,
            currentBrowserRestartRequired: settings.browserRestartRequired
        ) { summary in
            try await attachmentOwner.prepareCachedAttachmentService(for: appliedLevel)
            settings.setBrowserRestartRequired(true)
            lastApplySummary = summary
            lastApplyError = nil
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
        attachmentOwner.syncRuntime(for: appliedLevel)
        guard let requiredBundleProfileId = appliedLevel.preferredBundleProfileId else {
            clearPreparedBundleLookupDiagnostics()
            try await attachmentOwner.prepareCachedAttachmentService(for: appliedLevel)
            settings.setBrowserRestartRequired(false)
            lastApplyError = nil
            return nil
        }

        do {
            let manifest = try await bundleLifecycle.restorePreparedBundleForStartup(
                profileId: requiredBundleProfileId
            )
            try await attachmentOwner.prepareCachedAttachmentService(for: appliedLevel)
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
        attachmentOwner.normalTabDecision(
            for: url,
            profileId: profileId,
            requestedLevel: runtimeAppliedLevel
        )
    }

    func desiredAttachmentState(for url: URL?) -> SumiProtectionAttachmentState {
        attachmentOwner.desiredAttachmentState(
            for: url,
            requestedLevel: runtimeAppliedLevel
        )
    }

    func rulePlan(
        for url: URL?,
        profileId: UUID?,
        includeExpensiveDiagnostics: Bool = false
    ) -> SumiProtectionRulePlan {
        attachmentOwner.rulePlan(
            for: url,
            profileId: profileId,
            requestedLevel: runtimeAppliedLevel,
            includeExpensiveDiagnostics: includeExpensiveDiagnostics
        )
    }

    func cachedRulePlan(
        for url: URL?,
        profileId: UUID?
    ) -> SumiProtectionRulePlan {
        attachmentOwner.cachedRulePlan(
            for: url,
            profileId: profileId,
            requestedLevel: runtimeAppliedLevel
        )
    }

    private func clearPreparedBundleLookupDiagnostics() {
        bundleLifecycle.clearPreparedBundleLookupDiagnostics()
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
        return SumiProtectionDiagnosticsReporter.currentTabDiagnostics(
            for: url,
            appliedState: appliedState,
            reloadRequired: reloadRequired,
            reloadRequiredReason: reloadRequiredReason,
            didManualReloadRebuildWebView: didManualReloadRebuildWebView,
            appliedAfterManualReload: appliedAfterManualReload,
            actualAttachedRuleListIdentifiers: actualAttachedRuleListIdentifiers,
            contentBlockingAssetSummary: contentBlockingAssetSummary,
            webViewRebuildDuration: webViewRebuildDuration,
            urlHubSummaryDuration: urlHubSummaryDuration,
            plan: plan,
            planComputeDuration: planComputeDuration,
            contentBlockingServiceGenerationId: attachmentOwner.contentBlockingServiceGenerationId,
            bundleLookupDuration: bundleLifecycle.lastBundleLookupDuration
        )
    }

    func globalDiagnostics() -> SumiProtectionGlobalDiagnostics {
        let selectedLevel = settings.level
        let appliedLevel = settings.appliedLevel
        let manifest = selectedLevel == .off && appliedLevel == .off
            ? nil
            : adBlockingModule.activeManifestIfLoaded()
        let activePreparedProfileId = manifest.flatMap { attachmentOwner.preparedBundleProfileId(in: $0) }
        let requiredBundleProfileId = selectedLevel.preferredBundleProfileId
        let bundleDiagnostics = bundleLifecycle.diagnostics(
            manifest: manifest,
            requiredBundleProfileId: requiredBundleProfileId,
            activePreparedBundleProfileId: activePreparedProfileId
        )
        let trackingSourceAvailable = attachmentOwner.trackingSourceAvailable(manifest: manifest)
        let availableGroups = attachmentOwner.globallyAvailableGroups(
            manifest: manifest,
            trackingSourceAvailable: trackingSourceAvailable
        )
        let adblockBundleAvailable = requiredBundleProfileId.map {
            activePreparedProfileId == $0
        } ?? true

        return SumiProtectionDiagnosticsReporter.globalDiagnostics(
            selectedLevel: selectedLevel,
            appliedLevel: appliedLevel,
            browserRestartRequired: settings.browserRestartRequired,
            manifest: manifest,
            bundleDiagnostics: bundleDiagnostics,
            requiredBundleProfileId: requiredBundleProfileId,
            applyNeeded: applyNeeded,
            lastApplySummary: lastApplySummary,
            lastApplyError: lastApplyError,
            availableGroups: availableGroups,
            trackingSourceAvailable: trackingSourceAvailable,
            adblockBundleAvailable: adblockBundleAvailable,
            strictOffActive: selectedLevel == .off
                && appliedLevel == .off
                && attachmentOwner.isCacheEmpty
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
        SumiProtectionDiagnosticsReporter.copyDiagnosticsReport(
            global: globalDiagnostics(),
            plan: rulePlan(
                for: url,
                profileId: nil,
                includeExpensiveDiagnostics: true
            ),
            url: url,
            currentTabDiagnostics: currentTabDiagnostics,
            targetDescription: targetDescription,
            requestingURL: requestingURL,
            contentBlockingServiceGenerationId: attachmentOwner.contentBlockingServiceGenerationId,
            bundleLookupDuration: bundleLifecycle.lastBundleLookupDuration,
            startupSnapshot: SumiProtectionStartupRestoreDiagnostics.shared.latestSnapshot
        )
    }
#endif

    func setSiteOverride(_ override: SumiAdblockSiteOverride, for url: URL?) {
        adBlockingModule.setSiteOverride(override, for: url)
    }

    func sitePolicyChangesPublisher() -> AnyPublisher<Void, Never> {
        adBlockingModule.sitePolicyChangesPublisher()
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        attachmentOwner.surfaceEligibility(for: url)
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
}

enum SumiProtectionApplyError: LocalizedError {
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
