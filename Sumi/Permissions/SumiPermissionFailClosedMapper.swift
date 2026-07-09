import Foundation

enum SumiPermissionFailClosedMapper {
    static func temporaryPendingDecision(
        for context: SumiPermissionSecurityContext,
        reason: String,
        permissionTypes: [SumiPermissionType]? = nil
    ) -> SumiPermissionCoordinatorDecision {
        let resolvedPermissionTypes = permissionTypes ?? context.request.permissionTypes
        return SumiPermissionCoordinatorDecision(
            outcome: .promptRequired,
            state: .ask,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: resolvedPermissionTypes,
            keys: resolvedPermissionTypes.map { context.request.key(for: $0) },
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context.isEphemeralProfile
        )
    }

    /// Prefer `permissionTypes` when set (notifications / geolocation).
    /// Otherwise use `context.request.permissionTypes`, then `fallbackPermissionTypes` when context is nil.
    static func failClosedDecision(
        for context: SumiPermissionSecurityContext?,
        reason: String,
        permissionTypes: [SumiPermissionType]? = nil,
        fallbackPermissionTypes: [SumiPermissionType] = []
    ) -> SumiPermissionCoordinatorDecision {
        let resolvedPermissionTypes = permissionTypes
            ?? context?.request.permissionTypes
            ?? fallbackPermissionTypes
        let keys: [SumiPermissionKey]
        if let context {
            keys = resolvedPermissionTypes.map { context.request.key(for: $0) }
        } else {
            keys = []
        }
        return SumiPermissionCoordinatorDecision(
            outcome: .cancelled,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: resolvedPermissionTypes,
            keys: keys,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context?.isEphemeralProfile ?? false
        )
    }
}
