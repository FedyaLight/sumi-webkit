import Foundation
import SumiDomain

enum ProtectionAttachmentReadiness {
    static func validate(
        _ plan: SumiProtectionGlobalAttachmentPlan
    ) throws {
        if let requiredProfileID = plan.level.preferredBundleProfileId,
           plan.bundleProfileId != requiredProfileID {
            throw SumiProtectionApplyError.requiredGenerationUnavailable(
                profileId: requiredProfileID,
                detail: "The active generation after install is \(plan.bundleProfileId ?? "nil")."
            )
        }

        switch plan.level {
        case .off:
            return
        case .adblock:
            try require(
                .adblockAdsPrivacyNetwork,
                in: plan,
                profileID: SumiProtectionBundleProfile.adblock,
                detail: "No Adblock network rule lists were available after install."
            )
        }
    }

    private static func require(
        _ group: SumiProtectionGroupKind,
        in plan: SumiProtectionGlobalAttachmentPlan,
        profileID: String,
        detail: String
    ) throws {
        guard plan.activeGroups.contains(group) else {
            throw SumiProtectionApplyError.requiredGenerationUnavailable(
                profileId: profileID,
                detail: detail
            )
        }
    }
}
