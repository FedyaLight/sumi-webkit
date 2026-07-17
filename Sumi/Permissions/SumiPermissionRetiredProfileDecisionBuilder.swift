import Foundation
import SumiDomain

enum SumiPermissionRetiredProfileDecisionBuilder {
    static func make(
        for context: SumiPermissionSecurityContext
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .cancelled,
            state: .deny,
            persistence: nil,
            source: .cancelled,
            reason: "profile-retired",
            permissionTypes: context.request.permissionTypes,
            keys: context.request.permissionTypes.map {
                context.request.key(for: $0)
            }
        )
    }
}
