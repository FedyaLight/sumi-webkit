import Foundation

enum SumiPermissionPolicyResult: Equatable, Sendable {
    case proceed(
        source: SumiPermissionDecisionSource,
        reason: String,
        systemAuthorizationSnapshot: SumiSystemPermissionSnapshot?,
        mayOpenSystemSettings: Bool,
        allowedPersistences: Set<SumiPermissionPersistence>
    )
    case hardDeny(decision: SumiPermissionDecision)
    case systemBlocked(snapshot: SumiSystemPermissionSnapshot, decision: SumiPermissionDecision)
    case unsupported(decision: SumiPermissionDecision)
    case internalOnly(decision: SumiPermissionDecision)
    case requiresUserActivation(decision: SumiPermissionDecision)

    var isAllowedToProceed: Bool {
        if case .proceed = self {
            return true
        }
        return false
    }

    var mayOpenSystemSettings: Bool {
        switch self {
        case .proceed(_, _, _, let mayOpenSystemSettings, _):
            return mayOpenSystemSettings
        case .systemBlocked(let snapshot, _):
            return snapshot.shouldOpenSystemSettings
        case .hardDeny, .unsupported, .internalOnly, .requiresUserActivation:
            return false
        }
    }

    var allowedPersistences: Set<SumiPermissionPersistence> {
        if case .proceed(_, _, _, _, let allowedPersistences) = self {
            return allowedPersistences
        }
        return []
    }

    var decision: SumiPermissionDecision? {
        switch self {
        case .proceed:
            return nil
        case .hardDeny(let decision),
             .systemBlocked(_, let decision),
             .unsupported(let decision),
             .internalOnly(let decision),
             .requiresUserActivation(let decision):
            return decision
        }
    }

    var source: SumiPermissionDecisionSource {
        switch self {
        case .proceed(let source, _, _, _, _):
            return source
        case .hardDeny(let decision),
             .systemBlocked(_, let decision),
             .unsupported(let decision),
             .internalOnly(let decision),
             .requiresUserActivation(let decision):
            return decision.source
        }
    }

    var reason: String {
        switch self {
        case .proceed(_, let reason, _, _, _):
            return reason
        case .hardDeny(let decision),
             .systemBlocked(_, let decision),
             .unsupported(let decision),
             .internalOnly(let decision),
             .requiresUserActivation(let decision):
            return decision.reason ?? ""
        }
    }

    var systemAuthorizationSnapshot: SumiSystemPermissionSnapshot? {
        switch self {
        case .proceed(_, _, let snapshot, _, _):
            return snapshot
        case .systemBlocked(let snapshot, _):
            return snapshot
        case .hardDeny, .unsupported, .internalOnly, .requiresUserActivation:
            return nil
        }
    }
}
