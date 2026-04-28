import Foundation

enum SumiWebNotificationPermissionState: String, Codable, Equatable, Sendable {
    case granted
    case denied
    case `default`

    var permissionsAPIState: String {
        switch self {
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .default:
            return "prompt"
        }
    }
}

enum SumiWebNotificationDecisionMapper {
    static func permissionState(
        for decision: SumiPermissionCoordinatorDecision,
        promptRequiredState: SumiWebNotificationPermissionState = .default
    ) -> SumiWebNotificationPermissionState {
        switch decision.outcome {
        case .granted:
            switch decision.systemAuthorizationSnapshot?.state {
            case .authorized:
                return .granted
            case .notDetermined:
                return promptRequiredState
            case .denied,
                 .restricted,
                 .systemDisabled,
                 .unavailable,
                 .missingUsageDescription,
                 .missingEntitlement,
                 .none:
                return .denied
            }
        case .denied,
             .systemBlocked,
             .unsupported,
             .requiresUserActivation,
             .cancelled,
             .dismissed,
             .ignored,
             .expired:
            return .denied
        case .promptRequired:
            return promptRequiredState
        }
    }

    static func canDeliver(_ decision: SumiPermissionCoordinatorDecision) -> Bool {
        decision.outcome == .granted && isSystemAuthorized(decision)
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
            permissionTypes: [.notifications],
            keys: [context.request.key(for: .notifications)],
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
            permissionTypes: [.notifications],
            keys: context.map { [$0.request.key(for: .notifications)] } ?? [],
            shouldPersist: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context?.isEphemeralProfile ?? false
        )
    }

    private static func isSystemAuthorized(_ decision: SumiPermissionCoordinatorDecision) -> Bool {
        decision.systemAuthorizationSnapshot?.state == .authorized
    }
}
