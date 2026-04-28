import Foundation

enum SumiSystemPermissionAuthorizationState: String, Codable, CaseIterable, Hashable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case systemDisabled
    case unavailable
    case missingUsageDescription
    case missingEntitlement

    var canRequestFromSystem: Bool {
        self == .notDetermined
    }

    var shouldOpenSystemSettings: Bool {
        switch self {
        case .denied, .restricted, .systemDisabled:
            return true
        case .notDetermined, .authorized, .unavailable, .missingUsageDescription, .missingEntitlement:
            return false
        }
    }
}
