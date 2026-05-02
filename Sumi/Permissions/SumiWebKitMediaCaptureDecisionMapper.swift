import Foundation
import WebKit

enum SumiWebKitPermissionBridgePendingStrategy: Equatable, Sendable {
    case waitForPromptUI
    case promptPresenterUnavailableDeny

    var reason: String {
        switch self {
        case .waitForPromptUI:
            return "webkit-media-prompt-ui-wait"
        case .promptPresenterUnavailableDeny:
            return "webkit-media-prompt-presenter-unavailable-deny"
        }
    }

    var waitsForPromptUI: Bool {
        self == .waitForPromptUI
    }
}

enum SumiWebKitScreenCapturePendingStrategy: Equatable, Sendable {
    case waitForPromptUI
    case promptPresenterUnavailableDeny

    var reason: String {
        switch self {
        case .waitForPromptUI:
            return "webkit-screen-capture-prompt-ui-wait"
        case .promptPresenterUnavailableDeny:
            return "webkit-screen-capture-prompt-presenter-unavailable-deny"
        }
    }

    var waitsForPromptUI: Bool {
        self == .waitForPromptUI
    }
}

enum SumiWebKitDisplayCapturePermissionDecision: Int, Equatable, Sendable {
    case deny = 0
    case screenPrompt = 1
    case windowPrompt = 2
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
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context?.isEphemeralProfile ?? false
        )
    }
}

enum SumiWebKitDisplayCaptureDecisionMapper {
    static func permissionTypes(
        forLegacyCaptureDevices devices: SumiWebKitLegacyCaptureDevices
    ) -> [SumiPermissionType] {
        var permissionTypes: [SumiPermissionType] = []
        if devices.contains(.display) {
            permissionTypes.append(.screenCapture)
        }
        if devices.contains(.microphone) {
            permissionTypes.append(.microphone)
        }
        if devices.contains(.camera) {
            permissionTypes.append(.camera)
        }
        return permissionTypes
    }

    static func webKitDecision(
        for decision: SumiPermissionCoordinatorDecision
    ) -> SumiWebKitDisplayCapturePermissionDecision {
        decision.outcome == .granted ? .screenPrompt : .deny
    }

    static func legacyBoolDecision(
        for decision: SumiPermissionCoordinatorDecision
    ) -> Bool {
        decision.outcome == .granted
    }
}
