import Foundation

enum SumiGeolocationProviderState: Equatable, Hashable, Sendable {
    case inactive
    case active
    case paused
    case revoked
    case unavailable
    case failed(reason: String)
}
