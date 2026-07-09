import Foundation
import SumiDomain

struct SumiPermissionDecisionSideEffectOwner {
    typealias NowProvider = @Sendable () -> Date

    private let memoryStore: InMemoryPermissionStore
    private let persistentStore: (any SumiPermissionStore)?
    private let antiAbuseStore: (any SumiPermissionAntiAbuseStoring)?
    private let antiAbusePolicy: SumiPermissionAntiAbusePolicy
    private let sessionOwnerId: String?
    private let nowProvider: NowProvider

    init(
        memoryStore: InMemoryPermissionStore,
        persistentStore: (any SumiPermissionStore)?,
        antiAbuseStore: (any SumiPermissionAntiAbuseStoring)?,
        antiAbusePolicy: SumiPermissionAntiAbusePolicy,
        sessionOwnerId: String?,
        now: @escaping NowProvider
    ) {
        self.memoryStore = memoryStore
        self.persistentStore = persistentStore
        self.antiAbuseStore = antiAbuseStore
        self.antiAbusePolicy = antiAbusePolicy
        self.sessionOwnerId = sessionOwnerId
        self.nowProvider = now
    }

    func writeUserDecisionIfNeeded(
        pending: SumiPendingAuthorizationQuery,
        decision: SumiPermissionCoordinatorDecision
    ) async {
        guard let state = decision.state,
              let persistence = decision.persistence,
              decision.outcome != .ignored,
              decision.outcome != .dismissed,
              decision.outcome != .cancelled,
              decision.outcome != .expired
        else {
            return
        }

        let now = nowProvider()
        let storedDecision = SumiPermissionDecision(
            state: state,
            persistence: persistence,
            source: decision.source,
            reason: decision.reason,
            createdAt: now,
            updatedAt: now,
            systemAuthorizationSnapshot: SumiSystemPermissionSnapshot.encodedJSONString(for: decision.systemAuthorizationSnapshot)
        )

        switch persistence {
        case .oneTime, .session:
            guard persistence != .oneTime || pending.keys.allSatisfy({ supportsReusableOneTimeGrant($0.permissionType) }) else {
                return
            }
            for key in pending.keys {
                do {
                    try await memoryStore.setDecision(
                        for: key,
                        decision: storedDecision,
                        sessionOwnerId: sessionOwnerId
                    )
                } catch {
                    RuntimeDiagnostics.emit(
                        "[Permissions] Failed to store transient permission decision for \(key.permissionType.identity): \(error.localizedDescription)"
                    )
                }
            }
        case .persistent:
            guard let persistentStore else { return }
            for key in pending.keys
                where !key.isEphemeralProfile && key.permissionType.canBePersisted {
                do {
                    try await persistentStore.setDecision(for: key, decision: storedDecision)
                } catch {
                    RuntimeDiagnostics.emit(
                        "[Permissions] Failed to persist permission decision for \(key.permissionType.identity): \(error.localizedDescription)"
                    )
                    await writeFallbackSessionDecisionIfAllowed(
                        storedDecision,
                        key: key,
                        query: pending.query
                    )
                }
            }
        }
    }

    func clearSuppressionState(for key: SumiPermissionKey) async {
        await antiAbuseStore?.clearSuppressionState(for: key, now: nowProvider())
    }

    func recordManualSiteDecisionAntiAbuse(
        state: SumiPermissionState,
        key: SumiPermissionKey,
        reason: String?
    ) async {
        switch state {
        case .allow, .ask:
            await clearSuppressionState(for: key)
            if state == .allow {
                await recordEvents(
                    type: .userAllowed,
                    keys: [key],
                    reason: reason ?? "manual-site-decision"
                )
            }
        case .deny:
            await recordEvents(
                type: .userDenied,
                keys: [key],
                reason: reason ?? "manual-site-decision"
            )
        }
    }

    func recordSettlement(
        _ userDecision: SumiPermissionUserDecision,
        pending: SumiPendingAuthorizationQuery,
        decision: SumiPermissionCoordinatorDecision
    ) async {
        guard decision.outcome != .ignored else { return }
        switch userDecision {
        case .approveCurrentAttempt,
             .approveOnce,
             .approveForSession,
             .approvePersistently:
            for key in pending.keys {
                await clearSuppressionState(for: key)
            }
            await recordEvents(
                type: .userAllowed,
                keys: pending.keys,
                reason: decision.reason
            )
        case .denyOnce,
             .denyForSession,
             .denyPersistently:
            await recordEvents(
                type: .userDenied,
                keys: pending.keys,
                reason: decision.reason
            )
        case .dismiss:
            await recordEvents(
                type: .userDismissed,
                keys: pending.keys,
                reason: decision.reason
            )
        case .cancel:
            await recordEvents(
                type: .requestCancelledByNavigation,
                keys: pending.keys,
                reason: decision.reason
            )
        case .expire,
             .setAskPersistently:
            break
        }
    }

    func recordCancellation(
        _ decision: SumiPermissionCoordinatorDecision
    ) async {
        guard decision.outcome == .cancelled, !decision.keys.isEmpty else { return }
        await recordEvents(
            type: .requestCancelledByNavigation,
            keys: decision.keys,
            reason: decision.reason
        )
    }

    func recordEvents(
        type: SumiPermissionAntiAbuseEvent.EventType,
        keys: [SumiPermissionKey],
        reason: String?
    ) async {
        guard let antiAbuseStore else { return }
        let now = nowProvider()
        for key in keys {
            await antiAbuseStore.record(
                SumiPermissionAntiAbuseEvent(
                    type: type,
                    key: key,
                    createdAt: now,
                    reason: reason
                )
            )
        }
    }

    func systemBlockedSuppression(
        for decision: SumiPermissionCoordinatorDecision
    ) async -> SumiPermissionPromptSuppression? {
        guard let antiAbuseStore else { return nil }
        let now = nowProvider()
        for key in decision.keys {
            let events = await antiAbuseStore.events(for: key, now: now)
            if let suppression = antiAbusePolicy.systemBlockedSuppression(
                for: key,
                events: events,
                now: now
            ) {
                return suppression
            }
        }
        return nil
    }

    private func writeFallbackSessionDecisionIfAllowed(
        _ decision: SumiPermissionDecision,
        key: SumiPermissionKey,
        query: SumiPermissionAuthorizationQuery
    ) async {
        guard decision.state == .allow else { return }

        let fallbackPersistence: SumiPermissionPersistence
        if query.availablePersistences.contains(.session) {
            fallbackPersistence = .session
        } else if query.availablePersistences.contains(.oneTime),
                  supportsReusableOneTimeGrant(key.permissionType) {
            fallbackPersistence = .oneTime
        } else {
            return
        }

        let fallbackDecision = SumiPermissionDecision(
            state: decision.state,
            persistence: fallbackPersistence,
            source: decision.source,
            reason: "\(decision.reason ?? "permission-decision")-fallback-\(fallbackPersistence.rawValue)",
            createdAt: decision.createdAt,
            updatedAt: decision.updatedAt,
            expiresAt: decision.expiresAt,
            systemAuthorizationSnapshot: decision.systemAuthorizationSnapshot
        )
        do {
            try await memoryStore.setDecision(
                for: key,
                decision: fallbackDecision,
                sessionOwnerId: sessionOwnerId
            )
        } catch {
            RuntimeDiagnostics.emit(
                "[Permissions] Failed to store fallback permission decision for \(key.permissionType.identity): \(error.localizedDescription)"
            )
        }
    }

    private func supportsReusableOneTimeGrant(_ permissionType: SumiPermissionType) -> Bool {
        switch permissionType {
        case .camera, .microphone, .geolocation, .screenCapture:
            return true
        case .cameraAndMicrophone,
             .notifications,
             .popups,
             .externalScheme,
             .autoplay,
             .filePicker,
             .storageAccess:
            return false
        }
    }
}
