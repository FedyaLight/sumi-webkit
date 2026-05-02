import Foundation

enum SumiExternalSchemePermissionAction: Equatable, Sendable {
    case opened(SumiExternalSchemeAttemptRecord)
    case blocked(SumiExternalSchemeAttemptRecord)
    case unsupported(SumiExternalSchemeAttemptRecord)
    case openFailed(SumiExternalSchemeAttemptRecord)
}

struct SumiExternalSchemePermissionResult: Equatable, Sendable {
    let action: SumiExternalSchemePermissionAction
    var didOpen: Bool {
        if case .opened = action { return true }
        return false
    }
}

enum SumiExternalSchemeDecisionMapper {
    static func resultKind(
        for decision: SumiPermissionCoordinatorDecision,
        request: SumiExternalSchemePermissionRequest
    ) -> SumiExternalSchemeAttemptResult {
        switch decision.outcome {
        case .granted:
            return .opened
        case .denied where decision.source == .user:
            return .blockedByStoredDeny
        case .promptRequired:
            return request.isUserActivated ? .blockedPromptPresenterUnavailable : .blockedByDefault
        case .suppressed:
            return .blockedPromptPresenterUnavailable
        case .unsupported:
            return .unsupportedScheme
        case .requiresUserActivation,
             .denied,
             .systemBlocked,
             .cancelled,
             .dismissed,
             .ignored,
             .expired:
            return .blockedByDefault
        }
    }
}
