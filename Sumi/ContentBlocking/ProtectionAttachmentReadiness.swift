import Foundation
import SumiDomain

enum ProtectionAttachmentReadiness {
    static func validate(
        _ plan: SumiProtectionGlobalAttachmentPlan
    ) throws {
        if let requiredProfileID = plan.requiredBundleProfileId,
           plan.bundleProfileId != requiredProfileID {
            throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                profileId: requiredProfileID,
                detail: "The active prepared bundle after install is \(plan.bundleProfileId ?? "nil")."
            )
        }

        switch plan.level {
        case .off:
            return
        case .protection:
            try require(
                .trackingNetwork,
                in: plan,
                profileID: SumiProtectionBundleProfile.unified,
                detail: "No prepared trackingNetwork rule lists were available after install."
            )
        case .adblock:
            try require(
                .trackingNetwork,
                in: plan,
                profileID: SumiProtectionBundleProfile.unified,
                detail: "No prepared trackingNetwork rule lists were available after install."
            )
            try require(
                .adblockAdsPrivacyNetwork,
                in: plan,
                profileID: SumiProtectionBundleProfile.adblock,
                detail: "No adguardAdsPrivacy network rule lists were available after install."
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
            throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                profileId: profileID,
                detail: detail
            )
        }
    }
}
