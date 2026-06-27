import Foundation

struct SumiPermissionSettlementDecisionBuilder {
    func decision(
        for userDecision: SumiPermissionUserDecision,
        pending: SumiPendingAuthorizationQuery
    ) -> SumiPermissionCoordinatorDecision {
        let persistence = effectivePersistence(for: userDecision, query: pending.query)
        let outcome: SumiPermissionCoordinatorOutcome
        let state: SumiPermissionState?
        let source: SumiPermissionDecisionSource
        let reason: String

        switch userDecision {
        case .approveCurrentAttempt:
            outcome = .granted
            state = .allow
            source = .user
            reason = "approved-current-attempt"
        case .approveOnce:
            outcome = .granted
            state = .allow
            source = .user
            reason = "approved-once"
        case .approveForSession:
            outcome = .granted
            state = .allow
            source = .user
            reason = persistence == .session ? "approved-for-session" : "approved-for-session-downgraded"
        case .approvePersistently:
            outcome = .granted
            state = .allow
            source = .user
            reason = persistence == .persistent ? "approved-persistently" : "approved-persistently-downgraded"
        case .denyOnce:
            outcome = .denied
            state = .deny
            source = .user
            reason = "denied-once"
        case .denyForSession:
            outcome = .denied
            state = .deny
            source = .user
            reason = persistence == .session ? "denied-for-session" : "denied-for-session-downgraded"
        case .dismiss:
            outcome = .dismissed
            state = .ask
            source = .dismissed
            reason = "dismissed"
        case .denyPersistently:
            if persistence == .persistent {
                outcome = .denied
                state = .deny
                source = .user
                reason = "denied-persistently"
            } else {
                outcome = .ignored
                state = nil
                source = .runtime
                reason = "persistent-deny-unavailable"
            }
        case .setAskPersistently:
            if persistence == .persistent {
                outcome = .promptRequired
                state = .ask
                source = .user
                reason = "ask-persistently"
            } else {
                outcome = .ignored
                state = nil
                source = .runtime
                reason = "persistent-ask-unavailable"
            }
        case .cancel(let cancelReason):
            outcome = .cancelled
            state = nil
            source = .cancelled
            reason = cancelReason
        case .expire(let expireReason):
            outcome = .expired
            state = nil
            source = .runtime
            reason = expireReason
        }

        return SumiPermissionCoordinatorDecision(
            outcome: outcome,
            state: state,
            persistence: persistence,
            source: source,
            reason: reason,
            permissionTypes: pending.query.permissionTypes,
            keys: pending.keys,
            queryId: pending.query.id,
            systemAuthorizationSnapshot: pending.query.systemAuthorizationSnapshots.first,
            shouldOfferSystemSettings: pending.query.shouldOfferSystemSettings,
            disablesPersistentAllow: pending.query.disablesPersistentAllow
        )
    }

    private func effectivePersistence(
        for userDecision: SumiPermissionUserDecision,
        query: SumiPermissionAuthorizationQuery
    ) -> SumiPermissionPersistence? {
        switch userDecision {
        case .approveCurrentAttempt:
            return nil
        case .approveOnce, .denyOnce:
            return .oneTime
        case .approveForSession, .denyForSession:
            return query.availablePersistences.contains(.session) ? .session : .oneTime
        case .approvePersistently:
            if query.availablePersistences.contains(.persistent), !query.isEphemeralProfile {
                return .persistent
            }
            if query.availablePersistences.contains(.session) {
                return .session
            }
            return .oneTime
        case .denyPersistently, .setAskPersistently:
            return query.availablePersistences.contains(.persistent) && !query.isEphemeralProfile
                ? .persistent
                : nil
        case .dismiss, .cancel, .expire:
            return nil
        }
    }
}
