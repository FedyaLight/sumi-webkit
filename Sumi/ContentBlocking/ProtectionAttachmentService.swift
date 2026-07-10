import Foundation
import SumiDomain

@MainActor
final class ProtectionAttachmentService {
    private let ruleProvider: any ProtectionAttachmentRuleProviding
    private let siteNormalizer: SumiProtectionSiteNormalizer
    private let rulePlanner: SumiProtectionRulePlanner
    private let attachmentPlanner: ProtectionAttachmentPlanner
    private let bundleProjection: ProtectionPreparedBundleProjection
    private let cacheStore: ProtectionAttachmentCacheStore
    private let preparation: ProtectionAttachmentPreparation

    init(
        ruleProvider: any ProtectionAttachmentRuleProviding,
        siteNormalizer: SumiProtectionSiteNormalizer =
            SumiProtectionSiteNormalizer(),
        startupDiagnostics:
            (any SumiProtectionStartupRestoreDiagnosticsRecording)? = nil,
        contentBlockingServiceFactory:
            (@MainActor () -> SumiContentBlockingService)? = nil
    ) {
        let bundleProjection = ProtectionPreparedBundleProjection()
        let attachmentPlanner = ProtectionAttachmentPlanner(
            ruleProvider: ruleProvider,
            bundleProjection: bundleProjection
        )
        let cacheStore = ProtectionAttachmentCacheStore()
        #if DEBUG
            let diagnostics = startupDiagnostics
                ?? SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
            let serviceFactory = contentBlockingServiceFactory ?? {
                SumiContentBlockingService(
                    policy: .disabled,
                    startupDiagnostics: diagnostics
                )
            }
        #else
            let diagnostics = startupDiagnostics
            let serviceFactory = contentBlockingServiceFactory ?? {
                SumiContentBlockingService(policy: .disabled)
            }
        #endif

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
            startupDiagnostics: diagnostics,
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
        appliedLevel: SumiProtectionLevel,
        browserRestartRequired: Bool
    ) -> Bool {
        guard selectedLevel == appliedLevel else { return true }
        guard !browserRestartRequired else { return false }
        guard let requiredProfileID = selectedLevel.preferredBundleProfileId else {
            return false
        }
        guard let manifest = ruleProvider.activeManifestIfLoaded(),
              bundleProjection.preparedProfileID(in: manifest)
                == requiredProfileID
        else { return true }
        let availableGroups = Set(
            bundleProjection.groups(for: selectedLevel, in: manifest).map(\.group)
        )
        return !Set(selectedLevel.requestedGroups).isSubset(of: availableGroups)
    }

    func normalTabDecision(
        for url: URL?,
        profileId: UUID?,
        requestedLevel: SumiProtectionLevel
    ) -> SumiProtectionNormalTabDecision {
        let plan = cachedRulePlan(
            for: url,
            profileId: profileId,
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
            profileId: nil,
            requestedLevel: requestedLevel
        ).attachmentState
    }

    func rulePlan(
        for url: URL?,
        profileId: UUID?,
        requestedLevel: SumiProtectionLevel,
        includeExpensiveDiagnostics: Bool = false
    ) -> SumiProtectionRulePlan {
        makeRulePlan(
            for: url,
            profileId: profileId,
            requestedLevel: requestedLevel,
            includeExpensiveDiagnostics: includeExpensiveDiagnostics,
            loadRuleDefinitions: true
        )
    }

    func cachedRulePlan(
        for url: URL?,
        profileId: UUID?,
        requestedLevel: SumiProtectionLevel
    ) -> SumiProtectionRulePlan {
        makeRulePlan(
            for: url,
            profileId: profileId,
            requestedLevel: requestedLevel,
            includeExpensiveDiagnostics: false,
            loadRuleDefinitions: false
        )
    }

    func globalAttachmentPlan(
        for level: SumiProtectionLevel,
        includeExpensiveDiagnostics: Bool,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionGlobalAttachmentPlan {
        attachmentPlanner.globalPlan(
            for: level,
            manifest: ruleProvider.activeManifestIfLoaded(),
            cachedPlan: cacheStore.attachmentPlan,
            includeExpensiveDiagnostics: includeExpensiveDiagnostics,
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

    func trackingSourceAvailable(
        manifest: AdblockCompiledGenerationManifest?
    ) -> Bool {
        bundleProjection.trackingSourceAvailable(in: manifest)
    }

    func globallyAvailableGroups(
        manifest: AdblockCompiledGenerationManifest?,
        trackingSourceAvailable: Bool
    ) -> [SumiProtectionGroupKind] {
        bundleProjection.globallyAvailableGroups(
            in: manifest,
            trackingSourceAvailable: trackingSourceAvailable
        )
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        SumiAdblockSurfaceEligibility.evaluate(
            url: url,
            normalizer: siteNormalizer
        )
    }

    func preparedBundleProfileId(
        in manifest: AdblockCompiledGenerationManifest
    ) -> String? {
        bundleProjection.preparedProfileID(in: manifest)
    }

    private func makeRulePlan(
        for url: URL?,
        profileId: UUID?,
        requestedLevel: SumiProtectionLevel,
        includeExpensiveDiagnostics: Bool,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionRulePlan {
        _ = profileId
        let activeManifest = requestedLevel == .off
            ? nil
            : ruleProvider.activeManifestIfLoaded()
        return rulePlanner.makeRulePlan(
            for: url,
            requestedLevel: requestedLevel,
            activeManifest: activeManifest,
            includeExpensiveDiagnostics: includeExpensiveDiagnostics,
            loadRuleDefinitions: loadRuleDefinitions,
            siteOverrideProvider: { [ruleProvider] url in
                ruleProvider.siteOverride(for: url)
            },
            globalAttachmentPlanProvider: { level, includeDiagnostics, loadDefinitions in
                globalAttachmentPlan(
                    for: level,
                    includeExpensiveDiagnostics: includeDiagnostics,
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
