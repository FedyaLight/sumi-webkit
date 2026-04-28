import Foundation

enum SumiGeolocationProviderError: Error, Equatable, Hashable, Sendable {
    case permissionDenied
    case systemDisabled
    case unavailable
    case timeout
    case providerRevoked
    case providerPaused
    case unknown(String)

    var reason: String {
        switch self {
        case .permissionDenied:
            return "geolocation-permission-denied"
        case .systemDisabled:
            return "geolocation-system-disabled"
        case .unavailable:
            return "geolocation-unavailable"
        case .timeout:
            return "geolocation-timeout"
        case .providerRevoked:
            return "geolocation-provider-revoked"
        case .providerPaused:
            return "geolocation-provider-paused"
        case .unknown(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "geolocation-unknown" : trimmed
        }
    }
}
