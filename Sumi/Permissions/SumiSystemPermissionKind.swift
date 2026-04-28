import Foundation

enum SumiSystemPermissionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case camera
    case microphone
    case geolocation
    case notifications
    case screenCapture

    var displayLabel: String {
        switch self {
        case .camera:
            return "Camera"
        case .microphone:
            return "Microphone"
        case .geolocation:
            return "Location"
        case .notifications:
            return "Notifications"
        case .screenCapture:
            return "Screen Recording"
        }
    }
}
