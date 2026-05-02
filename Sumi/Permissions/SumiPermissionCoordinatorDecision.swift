import Foundation

enum SumiPermissionCoordinatorOutcome: String, Codable, CaseIterable, Hashable, Sendable {
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

struct SumiPermissionCoordinatorDecision: Equatable, Sendable {
    let outcome: SumiPermissionCoordinatorOutcome
    let state: SumiPermissionState?
    let persistence: SumiPermissionPersistence?
    let source: SumiPermissionDecisionSource
    let reason: String
    let permissionTypes: [SumiPermissionType]
    let keys: [SumiPermissionKey]
    let queryId: String?
    let systemAuthorizationSnapshot: SumiSystemPermissionSnapshot?
    let shouldOfferSystemSettings: Bool
    let disablesPersistentAllow: Bool
    let promptSuppression: SumiPermissionPromptSuppression?

    init(
        outcome: SumiPermissionCoordinatorOutcome,
        state: SumiPermissionState?,
        persistence: SumiPermissionPersistence?,
        source: SumiPermissionDecisionSource,
        reason: String,
        permissionTypes: [SumiPermissionType],
        keys: [SumiPermissionKey] = [],
        queryId: String? = nil,
        systemAuthorizationSnapshot: SumiSystemPermissionSnapshot? = nil,
        shouldOfferSystemSettings: Bool = false,
        disablesPersistentAllow: Bool = false,
        promptSuppression: SumiPermissionPromptSuppression? = nil
    ) {
        self.outcome = outcome
        self.state = state
        self.persistence = persistence
        self.source = source
        self.reason = reason
        self.permissionTypes = permissionTypes
        self.keys = keys
        self.queryId = queryId
        self.systemAuthorizationSnapshot = systemAuthorizationSnapshot
        self.shouldOfferSystemSettings = shouldOfferSystemSettings
        self.disablesPersistentAllow = disablesPersistentAllow
        self.promptSuppression = promptSuppression
    }

    static func fromPolicyResult(
        _ policyResult: SumiPermissionPolicyResult,
        context: SumiPermissionSecurityContext,
        permissionTypes: [SumiPermissionType]? = nil
    ) -> SumiPermissionCoordinatorDecision {
        let resolvedPermissionTypes = permissionTypes ?? context.request.permissionTypes
        let keys = resolvedPermissionTypes.map { context.request.key(for: $0) }
        let outcome: SumiPermissionCoordinatorOutcome
        switch policyResult {
        case .proceed:
            outcome = .promptRequired
        case .hardDeny, .internalOnly:
            outcome = .denied
        case .systemBlocked:
            outcome = .systemBlocked
        case .unsupported:
            outcome = .unsupported
        case .requiresUserActivation:
            outcome = .requiresUserActivation
        }

        return SumiPermissionCoordinatorDecision(
            outcome: outcome,
            state: policyResult.decision?.state,
            persistence: policyResult.decision?.persistence,
            source: policyResult.source,
            reason: policyResult.reason,
            permissionTypes: resolvedPermissionTypes,
            keys: keys,
            systemAuthorizationSnapshot: policyResult.systemAuthorizationSnapshot,
            shouldOfferSystemSettings: policyResult.mayOpenSystemSettings,
            disablesPersistentAllow: context.isEphemeralProfile
        )
    }

    static func fromStoredDecision(
        _ decision: SumiPermissionDecision,
        key: SumiPermissionKey,
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: decision.state == .allow ? .granted : .denied,
            state: decision.state,
            persistence: decision.persistence,
            source: decision.source,
            reason: reason,
            permissionTypes: [key.permissionType],
            keys: [key],
            systemAuthorizationSnapshot: Self.decodedSnapshot(decision.systemAuthorizationSnapshot),
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: key.isEphemeralProfile
        )
    }

    static func decodedSnapshot(_ snapshotString: String?) -> SumiSystemPermissionSnapshot? {
        guard let snapshotString,
              let data = snapshotString.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(SumiSystemPermissionSnapshot.self, from: data)
    }
}
