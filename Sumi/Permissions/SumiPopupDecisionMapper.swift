import Foundation

enum SumiPopupPermissionAction: Equatable, Sendable {
    case allow
    case block(SumiBlockedPopupRecord?)
}

struct SumiPopupPermissionResult: Equatable, Sendable {
    let action: SumiPopupPermissionAction
    let coordinatorDecision: SumiPermissionCoordinatorDecision?
    let reason: String

    var isAllowed: Bool {
        if case .allow = action { return true }
        return false
    }
}

enum SumiPopupDecisionMapper {
    static func defaultAllowDecision(
        for context: SumiPermissionSecurityContext,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .granted,
            state: .allow,
            persistence: nil,
            source: .defaultSetting,
            reason: reason,
            permissionTypes: [.popups],
            keys: [context.request.key(for: .popups)],
            shouldPersist: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context.isEphemeralProfile
        )
    }

    static func defaultBlockDecision(
        for context: SumiPermissionSecurityContext?,
        reason: String,
        source: SumiPermissionDecisionSource = .defaultSetting
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .denied,
            state: .deny,
            persistence: .session,
            source: source,
            reason: reason,
            permissionTypes: [.popups],
            keys: context.map { [$0.request.key(for: .popups)] } ?? [],
            shouldPersist: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context?.isEphemeralProfile ?? false
        )
    }

    static func blockedReason(for decision: SumiPermissionCoordinatorDecision) -> SumiBlockedPopupRecord.Reason {
        switch decision.outcome {
        case .denied where decision.source == .user:
            return .blockedByStoredDeny
        case .denied:
            return .blockedByPolicy
        case .requiresUserActivation:
            return .blockedByDefault
        case .unsupported:
            return .blockedByUnsupportedSurface
        case .promptRequired:
            return .blockedByPromptUIUnavailable
        case .systemBlocked, .cancelled, .dismissed, .suppressed, .ignored, .expired:
            return .blockedByPolicy
        case .granted:
            return .blockedByDefault
        }
    }
}
