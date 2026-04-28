import Foundation
import WebKit

enum SumiWebKitPermissionBridgePendingStrategy: Equatable, Sendable {
    case denyUntilPromptUIExists

    var reason: String {
        switch self {
        case .denyUntilPromptUIExists:
            return "webkit-media-prompt-ui-unavailable-deny"
        }
    }
}

enum SumiWebKitMediaCaptureDecisionMapper {
    @available(macOS 13.0, *)
    static func permissionTypes(for mediaType: WKMediaCaptureType) -> [SumiPermissionType] {
        switch mediaType {
        case .camera:
            return [.camera]
        case .microphone:
            return [.microphone]
        case .cameraAndMicrophone:
            return [.camera, .microphone]
        @unknown default:
            return []
        }
    }

    @available(macOS 13.0, *)
    static func webKitDecision(
        for decision: SumiPermissionCoordinatorDecision
    ) -> WKPermissionDecision {
        decision.outcome == .granted ? .grant : .deny
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
            permissionTypes: context?.request.permissionTypes ?? [],
            keys: context?.request.permissionTypes.map { context?.request.key(for: $0) }.compactMap { $0 } ?? [],
            shouldPersist: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context?.isEphemeralProfile ?? false
        )
    }
}
