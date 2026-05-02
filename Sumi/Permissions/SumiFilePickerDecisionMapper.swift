import Foundation

enum SumiFilePickerPermissionAction: Equatable, Sendable {
    case presentPanel
    case deny(reason: String)
}

enum SumiFilePickerDecisionMapper {
    static func action(
        for decision: SumiPermissionCoordinatorDecision
    ) -> SumiFilePickerPermissionAction {
        switch decision.outcome {
        case .granted, .promptRequired:
            return .presentPanel
        case .denied,
             .systemBlocked,
             .unsupported,
             .requiresUserActivation,
             .cancelled,
             .dismissed,
             .suppressed,
             .ignored,
             .expired:
            return .deny(reason: decision.reason)
        }
    }

}
