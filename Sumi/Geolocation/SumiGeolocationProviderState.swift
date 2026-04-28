import Foundation

enum SumiGeolocationProviderState: Equatable, Hashable, Sendable {
    case inactive
    case active
    case paused
    case revoked
    case unavailable
    case failed(reason: String)
}

extension SumiGeolocationProviderState {
    var isAvailableForWebKitGrant: Bool {
        switch self {
        case .inactive, .active, .paused:
            return true
        case .revoked, .unavailable, .failed:
            return false
        }
    }
}
