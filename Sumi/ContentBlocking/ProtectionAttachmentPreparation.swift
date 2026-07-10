import Foundation
import SumiDomain

@MainActor
final class ProtectionAttachmentPreparation {
    private let ruleProvider: any ProtectionAttachmentRuleProviding
    private let planner: ProtectionAttachmentPlanner
    private let bundleProjection: ProtectionPreparedBundleProjection
    private let cacheStore: ProtectionAttachmentCacheStore
    private let serviceFactory: @MainActor () -> SumiContentBlockingService
    #if DEBUG
        private let startupDiagnostics:
            any SumiProtectionStartupRestoreDiagnosticsRecording
    #endif

    init(
        ruleProvider: any ProtectionAttachmentRuleProviding,
        planner: ProtectionAttachmentPlanner,
        bundleProjection: ProtectionPreparedBundleProjection,
        cacheStore: ProtectionAttachmentCacheStore,
        startupDiagnostics:
            (any SumiProtectionStartupRestoreDiagnosticsRecording)?,
        serviceFactory: @escaping @MainActor () -> SumiContentBlockingService
    ) {
        self.ruleProvider = ruleProvider
        self.planner = planner
        self.bundleProjection = bundleProjection
        self.cacheStore = cacheStore
        self.serviceFactory = serviceFactory
        #if DEBUG
            self.startupDiagnostics = startupDiagnostics
                ?? SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
        #else
            _ = startupDiagnostics
        #endif
    }

    func prepare(for level: SumiProtectionLevel) async throws {
        guard level != .off else {
            cacheStore.clear()
            return
        }

        let metadataPlan = currentPlan(
            for: level,
            includeExpensiveDiagnostics: false,
            loadRuleDefinitions: false
        )
        #if DEBUG
            startupDiagnostics.recordExpectedShardIdentifiers(
                metadataPlan.expectedRuleListIdentifiers
            )
        #endif

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
                #if DEBUG
                    startupDiagnostics.recordMetadataOnlyRestoreUsed()
                #endif
                return
            } catch {
                #if DEBUG
                    let reason = "Protection attachment lookup-only restore failed: \(error.localizedDescription)"
                    startupDiagnostics.recordFallback(reason: reason)
                    startupDiagnostics.recordPayloadBackedRestoreUsed(
                        reason: reason
                    )
                    startupDiagnostics.recordRepairCompileUsed(reason: reason)
                #endif
            }
        }

        let payloadPlan = currentPlan(
            for: level,
            includeExpensiveDiagnostics: false,
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
        includeExpensiveDiagnostics: Bool,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionGlobalAttachmentPlan {
        planner.globalPlan(
            for: level,
            manifest: ruleProvider.activeManifestIfLoaded(),
            cachedPlan: cacheStore.attachmentPlan,
            includeExpensiveDiagnostics: includeExpensiveDiagnostics,
            loadRuleDefinitions: loadRuleDefinitions
        )
    }
}
