import Foundation

enum SumiPermissionDecisionSource: String, Codable, CaseIterable, Hashable, Sendable {
    case user
    case policy
    case system
    case insecureOrigin
    case permissionsPolicy
    case virtualURLMismatch
    case cooldown
    case embargo
    case defaultSetting
    case runtime
    case internalPage
    case invalidOrigin
    case unsupported
    case dismissed
    case cancelled
}
