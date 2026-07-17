import Foundation

struct SumiPermissionEventPublisher {
    private let sideEffects: SumiPermissionDecisionSideEffectOwner
    private let events: SumiPermissionCoordinatorEventStream

    init(
        sideEffects: SumiPermissionDecisionSideEffectOwner,
        events: SumiPermissionCoordinatorEventStream
    ) {
        self.sideEffects = sideEffects
        self.events = events
    }

    func snapshot() -> (
        latestEvent: SumiPermissionCoordinatorEvent?,
        latestSystemBlockedEvent: SumiPermissionCoordinatorEvent?
    ) {
        events.snapshot()
    }

    func stream() -> AsyncStream<SumiPermissionCoordinatorEvent> {
        events.events()
    }

    func emit(_ event: SumiPermissionCoordinatorEvent) {
        events.emit(event)
    }

    func publishIfNeeded(
        _ decision: SumiPermissionCoordinatorDecision
    ) async {
        guard decision.outcome == .systemBlocked else { return }
        if let suppression = await sideEffects.systemBlockedSuppression(
            for: decision
        ) {
            let suppressedDecision = SumiPermissionCoordinatorDecision(
                outcome: .systemBlocked,
                state: decision.state,
                persistence: decision.persistence,
                source: decision.source,
                reason: suppression.reason,
                permissionTypes: decision.permissionTypes,
                keys: decision.keys,
                queryId: decision.queryId,
                systemAuthorizationSnapshot: decision.systemAuthorizationSnapshot,
                shouldOfferSystemSettings: decision.shouldOfferSystemSettings,
                disablesPersistentAllow: decision.disablesPersistentAllow,
                promptSuppression: suppression
            )
            await sideEffects.recordEvents(
                type: suppression.eventType,
                keys: decision.keys,
                reason: suppression.reason
            )
            events.emit(.promptSuppressed(
                suppression,
                decision: suppressedDecision
            ))
            return
        }
        await sideEffects.recordEvents(
            type: .systemBlocked,
            keys: decision.keys,
            reason: decision.reason
        )
        events.emit(.systemBlocked(decision))
    }
}
