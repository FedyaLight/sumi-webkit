import Foundation
import SumiDomain

@MainActor
struct SumiProtectionRulePlanner {
    typealias SiteOverrideProvider = (URL?) -> SumiAdblockSiteOverride
    typealias GlobalAttachmentPlanProvider = (
        _ level: SumiProtectionLevel,
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
                loadRuleDefinitions
            )
            : emptyGlobalAttachmentPlanProvider(requestedLevel, activeManifest)

        let effectiveLevel = Self.effectiveLevel(for: globalPlan.activeGroups)

        return SumiProtectionRulePlan(
            requestedLevel: requestedLevel,
            effectiveLevel: effectiveLevel,
            siteHost: siteHost,
            sitePolicyAllowsProtection: siteAllowsProtection,
            activeGroups: globalPlan.activeGroups,
            activeGenerationId: globalPlan.activeGenerationId,
            expectedRuleListIdentifiers: globalPlan.expectedRuleListIdentifiers
        )
    }

    private static func effectiveLevel(
        for activeGroups: [SumiProtectionGroupKind]
    ) -> SumiProtectionLevel {
        if activeGroups.contains(.adblockAdsPrivacyNetwork) {
            return .adblock
        }
        return .off
    }
}

struct SumiProtectionGlobalAttachmentPlan: Equatable, Sendable {
    let level: SumiProtectionLevel
    let activeGroups: [SumiProtectionGroupKind]
    let expectedRuleListIdentifiers: [String]
    let ruleDefinitions: [SumiContentRuleListDefinition]
    let bundleProfileId: String?
    let activeGenerationId: String?

    var isAttachable: Bool {
        !activeGroups.isEmpty && !expectedRuleListIdentifiers.isEmpty
    }
}
