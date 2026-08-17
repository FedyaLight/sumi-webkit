import Foundation
import SumiDomain

@MainActor
final class ProtectionAttachmentPreparation {
    private let ruleProvider: any ProtectionAttachmentRuleProviding
    private let planner: ProtectionAttachmentPlanner
    private let bundleProjection: AdblockGenerationProjection
    private let cacheStore: ProtectionAttachmentCacheStore
    private let serviceFactory: @MainActor () -> SumiContentBlockingService
    init(
        ruleProvider: any ProtectionAttachmentRuleProviding,
        planner: ProtectionAttachmentPlanner,
        bundleProjection: AdblockGenerationProjection,
        cacheStore: ProtectionAttachmentCacheStore,
        serviceFactory: @escaping @MainActor () -> SumiContentBlockingService
    ) {
        self.ruleProvider = ruleProvider
        self.planner = planner
        self.bundleProjection = bundleProjection
        self.cacheStore = cacheStore
        self.serviceFactory = serviceFactory
    }

    func prepare(for level: SumiProtectionLevel) async throws {
        guard level != .off else {
            cacheStore.clear()
            return
        }

        let metadataPlan = currentPlan(
            for: level,
            loadRuleDefinitions: false
        )
        try ProtectionAttachmentReadiness.validate(metadataPlan)
        guard metadataPlan.isAttachable else {
            cacheStore.replace(
                with: planner.metadataOnlyPlan(metadataPlan),
                service: nil
            )
            return
        }

        let service = serviceFactory()
        let metadataOnlyDefinitions = bundleProjection.metadataOnlyRuleDefinitions(
            matching: metadataPlan.expectedRuleListIdentifiers,
            in: ruleProvider.activeManifestIfLoaded()
        )
        if metadataOnlyDefinitions.map(\.webKitStoreIdentifier).sorted()
            == metadataPlan.expectedRuleListIdentifiers.sorted() {
            do {
                let preparedUpdate = try await service
                    .prepareExistingRuleListUpdate(
                        ruleLists: metadataOnlyDefinitions
                    )
                service.commitPreparedContentBlockingUpdate(preparedUpdate)
                cacheStore.replace(
                    with: planner.metadataOnlyPlan(metadataPlan),
                    service: service
                )
                return
            } catch {}
        }

        let payloadPlan = currentPlan(
            for: level,
            loadRuleDefinitions: true
        )
        try ProtectionAttachmentReadiness.validate(payloadPlan)
        guard payloadPlan.isAttachable else {
            cacheStore.replace(
                with: planner.metadataOnlyPlan(payloadPlan),
                service: nil
            )
            return
        }

        let preparedUpdate = try await service.prepareRuleListUpdate(
            ruleLists: payloadPlan.ruleDefinitions,
            retainEncodedRuleListsInPreparedPolicy: false
        )
        service.commitPreparedContentBlockingUpdate(preparedUpdate)
        cacheStore.replace(
            with: planner.metadataOnlyPlan(payloadPlan),
            service: service
        )
    }

    private func currentPlan(
        for level: SumiProtectionLevel,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionGlobalAttachmentPlan {
        planner.globalPlan(
            for: level,
            manifest: ruleProvider.activeManifestIfLoaded(),
            cachedPlan: cacheStore.attachmentPlan,
            loadRuleDefinitions: loadRuleDefinitions
        )
    }
}
