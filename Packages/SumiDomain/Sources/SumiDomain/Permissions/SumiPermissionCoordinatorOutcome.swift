import Foundation

public enum SumiPermissionCoordinatorOutcome: String, Codable, CaseIterable, Hashable, Sendable {
    case granted
    case denied
    case promptRequired
    case systemBlocked
    case unsupported
    case requiresUserActivation
    case cancelled
    case dismissed
    case suppressed
    case ignored
    case expired
}
