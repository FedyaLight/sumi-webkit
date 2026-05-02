import Foundation

enum SumiPopupPermissionAction: Equatable, Sendable {
    case allow
    case block(SumiBlockedPopupRecord?)
}

struct SumiPopupPermissionResult: Equatable, Sendable {
    let action: SumiPopupPermissionAction
    var isAllowed: Bool {
        if case .allow = action { return true }
        return false
    }
}

enum SumiPopupDecisionMapper {
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
            return .blockedByBackgroundPromptUnavailable
        case .systemBlocked, .cancelled, .dismissed, .suppressed, .ignored, .expired:
            return .blockedByPolicy
        case .granted:
            return .blockedByDefault
        }
    }
}
