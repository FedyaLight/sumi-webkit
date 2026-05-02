import Foundation

struct SumiPermissionPolicyOverride: Equatable, Sendable {
    enum Action: String, Codable, Hashable, Sendable {
        case allow
        case deny
    }

    let action: Action
    let source: SumiPermissionDecisionSource
    let reason: String
}

protocol SumiPermissionPolicyProvider: Sendable {
    func override(
        for context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType
    ) async -> SumiPermissionPolicyOverride?
}

struct NoOpSumiPermissionPolicyProvider: SumiPermissionPolicyProvider {
    func override(
        for context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType
    ) async -> SumiPermissionPolicyOverride? {
        nil
    }
}
