import Foundation

struct SumiPermissionPolicyOverride: Equatable, Sendable {
    enum Action: String, Codable, Hashable, Sendable {
        case allow
        case deny
    }

    let action: Action
    let source: SumiPermissionDecisionSource
    let reason: String

    static func allow(
        source: SumiPermissionDecisionSource = .policy,
        reason: String = SumiPermissionPolicyReason.policyAllowed
    ) -> SumiPermissionPolicyOverride {
        SumiPermissionPolicyOverride(action: .allow, source: source, reason: reason)
    }

    static func deny(
        source: SumiPermissionDecisionSource = .policy,
        reason: String = SumiPermissionPolicyReason.policyDenied
    ) -> SumiPermissionPolicyOverride {
        SumiPermissionPolicyOverride(action: .deny, source: source, reason: reason)
    }
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
