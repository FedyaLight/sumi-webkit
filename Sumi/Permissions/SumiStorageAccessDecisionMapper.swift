import Foundation
import SumiDomain

enum SumiStorageAccessDecisionMapper {
    static func webKitDecision(
        for decision: SumiPermissionCoordinatorDecision
    ) -> Bool {
        decision.outcome == .granted
    }

    static func temporaryPendingDecision(
        for context: SumiPermissionSecurityContext,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionFailClosedMapper.temporaryPendingDecision(
            for: context,
            reason: reason
        )
    }

    static func failClosedDecision(
        for context: SumiPermissionSecurityContext?,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionFailClosedMapper.failClosedDecision(
            for: context,
            reason: reason,
            fallbackPermissionTypes: [.storageAccess]
        )
    }
}
