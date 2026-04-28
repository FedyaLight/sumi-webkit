import Foundation

enum SumiPermissionRuntimeControlResult: Equatable, Sendable {
    case applied(message: String)
    case noOp(message: String)
    case unsupported(message: String)
    case denied(message: String)
    case failed(message: String)

    var message: String {
        switch self {
        case .applied(let message),
             .noOp(let message),
             .unsupported(let message),
             .denied(let message),
             .failed(let message):
            return message
        }
    }

    var isError: Bool {
        switch self {
        case .applied, .noOp:
            return false
        case .unsupported, .denied, .failed:
            return true
        }
    }

    static func stalePage() -> SumiPermissionRuntimeControlResult {
        .failed(message: SumiPermissionRuntimeControlsStrings.pageChanged)
    }

    static func missingWebView() -> SumiPermissionRuntimeControlResult {
        .failed(message: SumiPermissionRuntimeControlsStrings.noCurrentPage)
    }

    static func locationNoLongerAllowed() -> SumiPermissionRuntimeControlResult {
        .denied(message: SumiPermissionRuntimeControlsStrings.locationNoLongerAllowed)
    }

    static func from(
        _ result: SumiRuntimePermissionOperationResult,
        actionKind: SumiPermissionRuntimeControl.Action.Kind
    ) -> SumiPermissionRuntimeControlResult {
        switch result {
        case .applied:
            return .applied(message: appliedMessage(for: actionKind))
        case .noOp:
            return .noOp(message: SumiPermissionRuntimeControlsStrings.alreadyCurrent)
        case .unsupported:
            return .unsupported(message: SumiPermissionRuntimeControlsStrings.unavailableInWebKit)
        case .deniedByRuntime:
            return .denied(message: deniedMessage(for: actionKind))
        case .failed:
            return .failed(message: SumiPermissionRuntimeControlsStrings.updateFailed)
        case .requiresReload:
            return .applied(message: SumiPermissionRuntimeControlsStrings.autoplayReloadRequired)
        }
    }

    private static func appliedMessage(
        for actionKind: SumiPermissionRuntimeControl.Action.Kind
    ) -> String {
        switch actionKind {
        case .muteCamera:
            return SumiPermissionRuntimeControlsStrings.cameraMutedResult
        case .unmuteCamera:
            return SumiPermissionRuntimeControlsStrings.cameraUnmutedResult
        case .stopCamera:
            return SumiPermissionRuntimeControlsStrings.cameraStoppedResult
        case .muteMicrophone:
            return SumiPermissionRuntimeControlsStrings.microphoneMutedResult
        case .unmuteMicrophone:
            return SumiPermissionRuntimeControlsStrings.microphoneUnmutedResult
        case .stopMicrophone:
            return SumiPermissionRuntimeControlsStrings.microphoneStoppedResult
        case .pauseGeolocation:
            return SumiPermissionRuntimeControlsStrings.locationPausedResult
        case .resumeGeolocation:
            return SumiPermissionRuntimeControlsStrings.locationResumedResult
        case .stopGeolocationForVisit:
            return SumiPermissionRuntimeControlsStrings.locationStoppedResult
        case .reloadAutoplay:
            return SumiPermissionRuntimeControlsStrings.autoplayReloadingResult
        }
    }

    private static func deniedMessage(
        for actionKind: SumiPermissionRuntimeControl.Action.Kind
    ) -> String {
        switch actionKind {
        case .resumeGeolocation:
            return SumiPermissionRuntimeControlsStrings.locationNoLongerAllowed
        default:
            return SumiPermissionRuntimeControlsStrings.updateFailed
        }
    }
}
