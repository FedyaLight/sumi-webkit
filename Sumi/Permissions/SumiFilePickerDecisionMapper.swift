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
            permissionTypes: context?.request.permissionTypes ?? [.filePicker],
            keys: context?.request.permissionTypes.map { context?.request.key(for: $0) }.compactMap { $0 } ?? [],
            shouldPersist: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: true
        )
    }
}
