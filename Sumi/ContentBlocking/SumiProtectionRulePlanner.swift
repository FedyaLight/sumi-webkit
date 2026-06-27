import Foundation

@MainActor
struct SumiProtectionRulePlanner {
    typealias SiteOverrideProvider = (URL?) -> SumiAdblockSiteOverride
    typealias GlobalAttachmentPlanProvider = (
        _ level: SumiProtectionLevel,
        _ includeExpensiveDiagnostics: Bool,
        _ loadRuleDefinitions: Bool
    ) -> SumiProtectionGlobalAttachmentPlan
    typealias EmptyGlobalAttachmentPlanProvider = (
        _ level: SumiProtectionLevel,
        _ manifest: AdblockCompiledGenerationManifest?
    ) -> SumiProtectionGlobalAttachmentPlan

    let siteNormalizer: SumiProtectionSiteNormalizer

    init(siteNormalizer: SumiProtectionSiteNormalizer = SumiProtectionSiteNormalizer()) {
        self.siteNormalizer = siteNormalizer
    }

    func makeRulePlan(
        for url: URL?,
        requestedLevel: SumiProtectionLevel,
        activeManifest: AdblockCompiledGenerationManifest?,
        includeExpensiveDiagnostics: Bool,
        loadRuleDefinitions: Bool,
        siteOverrideProvider: SiteOverrideProvider,
        globalAttachmentPlanProvider: GlobalAttachmentPlanProvider,
        emptyGlobalAttachmentPlanProvider: EmptyGlobalAttachmentPlanProvider
    ) -> SumiProtectionRulePlan {
        let eligibility = SumiAdblockSurfaceEligibility.evaluate(
            url: url,
            normalizer: siteNormalizer
        )
        let siteHost = eligibility.normalizedSiteHost
        let shouldConsultSiteOverride = requestedLevel != .off && eligibility.isEligible
        let siteOverride = shouldConsultSiteOverride
            ? siteOverrideProvider(url)
            : .inherit
        let siteAllowsProtection = requestedLevel != .off
            && eligibility.isEligible
            && siteOverride != .disabled

        let globalPlan = siteAllowsProtection
            ? globalAttachmentPlanProvider(
                requestedLevel,
                includeExpensiveDiagnostics,
                loadRuleDefinitions
            )
            : emptyGlobalAttachmentPlanProvider(requestedLevel, activeManifest)

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
}

struct SumiProtectionGlobalAttachmentPlan: Equatable, Sendable {
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
