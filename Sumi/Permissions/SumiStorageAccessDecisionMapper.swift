import Foundation

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
        SumiPermissionCoordinatorDecision(
            outcome: .promptRequired,
            state: .ask,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: context.request.permissionTypes,
            keys: context.request.permissionTypes.map { context.request.key(for: $0) },
            shouldPersist: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context.isEphemeralProfile
        )
    }

    static func failClosedDecision(
        for context: SumiPermissionSecurityContext?,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .cancelled,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: context?.request.permissionTypes ?? [.storageAccess],
            keys: context?.request.permissionTypes.map { context?.request.key(for: $0) }.compactMap { $0 } ?? [],
            shouldPersist: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context?.isEphemeralProfile ?? false
        )
    }
}
