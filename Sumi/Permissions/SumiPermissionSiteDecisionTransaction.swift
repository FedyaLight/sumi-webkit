import Foundation
import SumiDomain

struct SumiPermissionSiteDecisionTransaction {
    typealias NowProvider = @Sendable () -> Date

    private let memoryStore: InMemoryPermissionStore
    private let persistentStore: (any SumiPermissionStore)?
    private let sideEffects: SumiPermissionDecisionSideEffectOwner
    private let sessionOwnerID: String?
    private let now: NowProvider

    init(
        memoryStore: InMemoryPermissionStore,
        persistentStore: (any SumiPermissionStore)?,
        sideEffects: SumiPermissionDecisionSideEffectOwner,
        sessionOwnerID: String?,
        now: @escaping NowProvider
    ) {
        self.memoryStore = memoryStore
        self.persistentStore = persistentStore
        self.sideEffects = sideEffects
        self.sessionOwnerID = sessionOwnerID
        self.now = now
    }

    func set(
        _ state: SumiPermissionState,
        for key: SumiPermissionKey,
        source: SumiPermissionDecisionSource,
        reason: String?
    ) async throws {
        guard key.permissionType.canBePersisted else {
            throw SumiPermissionSiteDecisionError.unsupportedPermission(
                key.permissionType.identity
            )
        }
        let timestamp = now()
        let persistence: SumiPermissionPersistence = key.isEphemeralProfile
            ? .session
            : .persistent
        let decision = SumiPermissionDecision(
            state: state,
            persistence: persistence,
            source: source,
            reason: reason,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        if key.isEphemeralProfile {
            try await memoryStore.setDecision(
                for: key,
                decision: decision,
                sessionOwnerId: sessionOwnerID
            )
        } else {
            guard let persistentStore else {
                throw SumiPermissionSiteDecisionError.persistentStoreUnavailable
            }
            try await persistentStore.setDecision(for: key, decision: decision)
        }
        await sideEffects.recordManualSiteDecisionAntiAbuse(
            state: state,
            key: key,
            reason: reason
        )
    }

    func reset(_ key: SumiPermissionKey) async throws {
        try await memoryStore.resetDecision(
            for: key,
            sessionOwnerId: sessionOwnerID
        )
        await sideEffects.clearSuppressionState(for: key)
        if key.isEphemeralProfile == false {
            try await persistentStore?.resetDecision(for: key)
        }
    }
}
