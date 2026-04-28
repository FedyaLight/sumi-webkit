import Foundation

enum SumiRuntimePermissionOperation: Hashable, Sendable {
    case setCameraMuted(Bool)
    case setMicrophoneMuted(Bool)
    case stopCamera
    case stopMicrophone
    case stopAllMediaCapture
    case revoke(SumiPermissionType)
    case pause(SumiPermissionType)
    case resume(SumiPermissionType)
    case autoplay(SumiRuntimeAutoplayState)
}
