import Foundation

enum SumiMediaCaptureRuntimeState: String, Codable, CaseIterable, Hashable, Sendable {
    case unavailable
    case none
    case active
    case muted
    case stopping
    case revoking
    case unsupported

    var hasActiveStream: Bool {
        switch self {
        case .active, .muted, .stopping, .revoking:
            return true
        case .unavailable, .none, .unsupported:
            return false
        }
    }
}

enum SumiGeolocationRuntimeState: String, Codable, CaseIterable, Hashable, Sendable {
    case unavailable
    case none
    case active
    case paused
    case revoked
    case unsupportedProvider
}

enum SumiRuntimeAutoplayState: String, Codable, CaseIterable, Hashable, Sendable {
    case allowAll
    case blockAudible
    case blockAll
    case reloadRequired
    case unsupported
}

enum SumiNonDeviceRuntimeState: String, Codable, CaseIterable, Hashable, Sendable {
    case noActiveRuntimeState
    case unsupported
}

struct SumiCameraAndMicrophoneRuntimeState: Codable, Equatable, Hashable, Sendable {
    var camera: SumiMediaCaptureRuntimeState
    var microphone: SumiMediaCaptureRuntimeState

    var hasAnyActiveStream: Bool {
        camera.hasActiveStream || microphone.hasActiveStream
    }
}

struct SumiRuntimePermissionState: Codable, Equatable, Hashable, Sendable {
    var camera: SumiMediaCaptureRuntimeState
    var microphone: SumiMediaCaptureRuntimeState
    var screenCapture: SumiMediaCaptureRuntimeState
    var cameraAndMicrophone: SumiCameraAndMicrophoneRuntimeState
    var geolocation: SumiGeolocationRuntimeState
    var notifications: SumiNonDeviceRuntimeState
    var popups: SumiNonDeviceRuntimeState
    var externalScheme: SumiNonDeviceRuntimeState
    var autoplay: SumiRuntimeAutoplayState
    var filePicker: SumiNonDeviceRuntimeState
    var storageAccess: SumiNonDeviceRuntimeState

    init(
        camera: SumiMediaCaptureRuntimeState,
        microphone: SumiMediaCaptureRuntimeState,
        screenCapture: SumiMediaCaptureRuntimeState = .unsupported,
        geolocation: SumiGeolocationRuntimeState = .unsupportedProvider,
        notifications: SumiNonDeviceRuntimeState = .noActiveRuntimeState,
        popups: SumiNonDeviceRuntimeState = .noActiveRuntimeState,
        externalScheme: SumiNonDeviceRuntimeState = .noActiveRuntimeState,
        autoplay: SumiRuntimeAutoplayState = .allowAll,
        filePicker: SumiNonDeviceRuntimeState = .noActiveRuntimeState,
        storageAccess: SumiNonDeviceRuntimeState = .unsupported
    ) {
        self.camera = camera
        self.microphone = microphone
        self.screenCapture = screenCapture
        self.cameraAndMicrophone = SumiCameraAndMicrophoneRuntimeState(
            camera: camera,
            microphone: microphone
        )
        self.geolocation = geolocation
        self.notifications = notifications
        self.popups = popups
        self.externalScheme = externalScheme
        self.autoplay = autoplay
        self.filePicker = filePicker
        self.storageAccess = storageAccess
    }

}
