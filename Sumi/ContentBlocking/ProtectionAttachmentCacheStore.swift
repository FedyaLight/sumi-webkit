import Foundation

@MainActor
final class ProtectionAttachmentCacheStore {
    private(set) var attachmentPlan: SumiProtectionGlobalAttachmentPlan?
    private var contentBlockingService: SumiContentBlockingService?
    private(set) var generationID: UInt64 = 0

    var isEmpty: Bool {
        attachmentPlan == nil && contentBlockingService == nil
    }

    func contentBlockingService(
        for plan: SumiProtectionRulePlan,
        cachedPlanMatchesActiveManifest: Bool
    ) -> SumiContentBlockingService? {
        guard plan.sitePolicyAllowsProtection,
              !plan.expectedRuleListIdentifiers.isEmpty,
              cachedPlanMatchesActiveManifest,
              let contentBlockingService,
              contentBlockingService.latestRuleListIdentifiers
                == plan.expectedRuleListIdentifiers
        else { return nil }
        return contentBlockingService
    }

    func replace(
        with metadataOnlyPlan: SumiProtectionGlobalAttachmentPlan,
        service: SumiContentBlockingService?
    ) {
        attachmentPlan = metadataOnlyPlan
        contentBlockingService = service
        generationID &+= 1
    }

    func clear() {
        attachmentPlan = nil
        contentBlockingService = nil
        generationID &+= 1
    }
}
