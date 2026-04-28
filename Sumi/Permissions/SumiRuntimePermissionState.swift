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
    case muteAudio
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

    func state(for permissionType: SumiPermissionType) -> SumiRuntimePermissionStateValue {
        switch permissionType {
        case .camera:
            return .media(camera)
        case .microphone:
            return .media(microphone)
        case .cameraAndMicrophone:
            return .cameraAndMicrophone(cameraAndMicrophone)
        case .geolocation:
            return .geolocation(geolocation)
        case .notifications:
            return .nonDevice(notifications)
        case .popups:
            return .nonDevice(popups)
        case .externalScheme:
            return .nonDevice(externalScheme)
        case .autoplay:
            return .autoplay(autoplay)
        case .filePicker:
            return .nonDevice(filePicker)
        case .storageAccess:
            return .nonDevice(storageAccess)
        }
    }
}

enum SumiRuntimePermissionStateValue: Equatable, Hashable, Sendable {
    case media(SumiMediaCaptureRuntimeState)
    case cameraAndMicrophone(SumiCameraAndMicrophoneRuntimeState)
    case geolocation(SumiGeolocationRuntimeState)
    case autoplay(SumiRuntimeAutoplayState)
    case nonDevice(SumiNonDeviceRuntimeState)
}
