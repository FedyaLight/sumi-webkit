import Foundation

@MainActor
final class PendingShortcutPinAdopter {
    enum Result {
        case noChange
        case adopted
        case deferred
    }

    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let persistence: TabStructuralPersistenceService
    private var deferredProfileID: UUID?
    private var availabilityObservationID: UUID?

    var hasDeferredAdoption: Bool {
        deferredProfileID != nil
    }

    init(
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        persistence: TabStructuralPersistenceService
    ) {
        self.pins = pins
        self.structuralMutations = structuralMutations
        self.persistence = persistence
    }

    @discardableResult
    func adoptPendingPins(into profileID: UUID) -> Result {
        deferredProfileID = profileID
        return attemptAdoption()
    }

    func cancelDeferredAdoption() {
        deferredProfileID = nil
        if let availabilityObservationID {
            structuralMutations.cancelAvailabilityObservation(
                availabilityObservationID
            )
            self.availabilityObservationID = nil
        }
    }

    private func attemptAdoption() -> Result {
        guard let profileID = deferredProfileID else { return .noChange }
        let pending = pins.pendingPinnedWithoutProfileSnapshot()
        guard pending.isEmpty == false else {
            cancelDeferredAdoption()
            return .noChange
        }
        guard let aggregate = structuralMutations.prepareAggregate() else {
            observeAvailabilityIfNeeded()
            return .deferred
        }

        let expected = pending.map(ObjectIdentifier.init)
        let drained = pins.drainPendingPinnedWithoutProfile()
        precondition(
            drained.map(ObjectIdentifier.init) == expected,
            "Pending-pin source changed during synchronous adoption"
        )
        let destination = pins.pinnedByProfileSnapshot()[profileID, default: []]
        structuralMutations.setPinnedTabs(
            ShortcutPin.reindexed(destination + drained),
            for: profileID
        )
        precondition(aggregate.stage())
        precondition(aggregate.publish())
        persistence.scheduleStructuralPersistence()
        cancelDeferredAdoption()
        return .adopted
    }

    private func observeAvailabilityIfNeeded() {
        guard availabilityObservationID == nil else { return }
        availabilityObservationID = structuralMutations
            .observeNextAvailability { [weak self] in
                guard let self else { return }
                self.availabilityObservationID = nil
                _ = self.attemptAdoption()
            }
        if availabilityObservationID == nil {
            _ = attemptAdoption()
        }
    }
}
