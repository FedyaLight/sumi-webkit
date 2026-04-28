import Foundation

enum SumiSystemPermissionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case camera
    case microphone
    case geolocation
    case notifications

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
        }
    }
}
