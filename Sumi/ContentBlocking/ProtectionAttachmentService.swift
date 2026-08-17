import Foundation
import SumiDomain

@MainActor
final class ProtectionAttachmentService {
    private let ruleProvider: any ProtectionAttachmentRuleProviding
    private let siteNormalizer: SumiProtectionSiteNormalizer
    private let rulePlanner: SumiProtectionRulePlanner
    private let attachmentPlanner: ProtectionAttachmentPlanner
    private let bundleProjection: AdblockGenerationProjection
    private let cacheStore: ProtectionAttachmentCacheStore
    private let preparation: ProtectionAttachmentPreparation

    init(
        ruleProvider: any ProtectionAttachmentRuleProviding,
        siteNormalizer: SumiProtectionSiteNormalizer =
            SumiProtectionSiteNormalizer(),
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        contentBlockingServiceFactory:
            (@MainActor () -> SumiContentBlockingService)? = nil
    ) {
        let bundleProjection = AdblockGenerationProjection()
        let attachmentPlanner = ProtectionAttachmentPlanner(
            ruleProvider: ruleProvider,
            bundleProjection: bundleProjection
        )
        let cacheStore = ProtectionAttachmentCacheStore()
        let serviceFactory = contentBlockingServiceFactory ?? {
            SumiContentBlockingService(
                policy: .disabled,
                compiledRuleListCatalog: compiledRuleListCatalog
            )
        }

        self.ruleProvider = ruleProvider
        self.siteNormalizer = siteNormalizer
        rulePlanner = SumiProtectionRulePlanner(siteNormalizer: siteNormalizer)
        self.attachmentPlanner = attachmentPlanner
        self.bundleProjection = bundleProjection
        self.cacheStore = cacheStore
        preparation = ProtectionAttachmentPreparation(
            ruleProvider: ruleProvider,
            planner: attachmentPlanner,
            bundleProjection: bundleProjection,
            cacheStore: cacheStore,
            serviceFactory: serviceFactory
        )
    }

    var contentBlockingServiceGenerationId: UInt64 {
        cacheStore.generationID
    }

    var isCacheEmpty: Bool {
        cacheStore.isEmpty
    }

    func syncRuntime(for level: SumiProtectionLevel) {
        ruleProvider.setRuntimeLevel(level)
    }

    func applyNeeded(
        selectedLevel: SumiProtectionLevel,
        appliedLevel: SumiProtectionLevel
    ) -> Bool {
        guard selectedLevel == appliedLevel else { return true }
        guard let requiredProfileID = selectedLevel.preferredBundleProfileId else {
            return false
        }
        guard let manifest = ruleProvider.activeManifestIfLoaded(),
              bundleProjection.profileID(in: manifest)
                == requiredProfileID
        else { return true }
        let availableGroups = Set(
            bundleProjection.groups(for: selectedLevel, in: manifest).map(\.group)
        )
        return !Set(selectedLevel.requestedGroups).isSubset(of: availableGroups)
    }

    func normalTabDecision(
        for url: URL?,
        requestedLevel: SumiProtectionLevel
    ) -> SumiProtectionNormalTabDecision {
        let plan = cachedRulePlan(
            for: url,
            requestedLevel: requestedLevel
        )
        return SumiProtectionNormalTabDecision(
            plan: plan,
            contentBlockingService: cachedContentBlockingService(for: plan)
        )
    }

    func desiredAttachmentState(
        for url: URL?,
        requestedLevel: SumiProtectionLevel
    ) -> SumiProtectionAttachmentState {
        cachedRulePlan(
            for: url,
            requestedLevel: requestedLevel
        ).attachmentState
    }

    func rulePlan(
        for url: URL?,
        requestedLevel: SumiProtectionLevel
    ) -> SumiProtectionRulePlan {
        makeRulePlan(
            for: url,
            requestedLevel: requestedLevel,
            loadRuleDefinitions: true
        )
    }

    func cachedRulePlan(
        for url: URL?,
        requestedLevel: SumiProtectionLevel
    ) -> SumiProtectionRulePlan {
        makeRulePlan(
            for: url,
            requestedLevel: requestedLevel,
            loadRuleDefinitions: false
        )
    }

    func globalAttachmentPlan(
        for level: SumiProtectionLevel,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionGlobalAttachmentPlan {
        attachmentPlanner.globalPlan(
            for: level,
            manifest: ruleProvider.activeManifestIfLoaded(),
            cachedPlan: cacheStore.attachmentPlan,
            loadRuleDefinitions: loadRuleDefinitions
        )
    }

    func prepareCachedAttachmentService(
        for level: SumiProtectionLevel
    ) async throws {
        try await preparation.prepare(for: level)
    }

    func validateRequiredGroupsReady(
        in plan: SumiProtectionGlobalAttachmentPlan
    ) throws {
        try ProtectionAttachmentReadiness.validate(plan)
    }

    func clearCachedAttachmentService() {
        cacheStore.clear()
    }

    func globallyAvailableGroups(
        manifest: AdblockCompiledGenerationManifest?
    ) -> [SumiProtectionGroupKind] {
        bundleProjection.globallyAvailableGroups(in: manifest)
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        SumiAdblockSurfaceEligibility.evaluate(
            url: url,
            normalizer: siteNormalizer
        )
    }

    func activeGenerationProfileID(
        in manifest: AdblockCompiledGenerationManifest
    ) -> String? {
        bundleProjection.profileID(in: manifest)
    }

    private func makeRulePlan(
        for url: URL?,
        requestedLevel: SumiProtectionLevel,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionRulePlan {
        let activeManifest = requestedLevel == .off
            ? nil
            : ruleProvider.activeManifestIfLoaded()
        return rulePlanner.makeRulePlan(
            for: url,
            requestedLevel: requestedLevel,
            activeManifest: activeManifest,
            loadRuleDefinitions: loadRuleDefinitions,
            siteOverrideProvider: { [ruleProvider] url in
                ruleProvider.siteOverride(for: url)
            },
            globalAttachmentPlanProvider: { level, loadDefinitions in
                globalAttachmentPlan(
                    for: level,
                    loadRuleDefinitions: loadDefinitions
                )
            },
            emptyGlobalAttachmentPlanProvider: { [attachmentPlanner] level, manifest in
                attachmentPlanner.emptyPlan(for: level, manifest: manifest)
            }
        )
    }

    private func cachedContentBlockingService(
        for plan: SumiProtectionRulePlan
    ) -> SumiContentBlockingService? {
        let manifest = ruleProvider.activeManifestIfLoaded()
        let cachedPlanMatchesManifest = cacheStore.attachmentPlan.map {
            attachmentPlanner.matches(
                $0,
                level: plan.requestedLevel,
                manifest: manifest
            )
        } ?? false
        return cacheStore.contentBlockingService(
            for: plan,
            cachedPlanMatchesActiveManifest: cachedPlanMatchesManifest
        )
    }
}
