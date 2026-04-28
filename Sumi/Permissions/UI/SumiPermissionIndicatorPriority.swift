import Foundation

enum SumiPermissionIndicatorPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case activeScreenCapture = 10
    case activeCameraAndMicrophone = 20
    case activeCamera = 30
    case activeMicrophone = 40
    case activeGeolocation = 50
    case pendingSensitiveRequest = 60
    case systemBlockedSensitive = 70
    case blockedPopup = 80
    case blockedExternalScheme = 90
    case blockedNotification = 100
    case autoplayReloadRequired = 110
    case storageAccessBlockedOrPending = 120
    case filePickerCurrentEvent = 130
    case genericPermissionsFallback = 140

    static func < (
        lhs: SumiPermissionIndicatorPriority,
        rhs: SumiPermissionIndicatorPriority
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
