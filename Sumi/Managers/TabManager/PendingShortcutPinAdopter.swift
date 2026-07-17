import Foundation

@MainActor
final class PendingShortcutPinAdopter {
    private struct DeferredAdoption {
        let profileID: UUID
        let admission: ProfileReferenceAdmissionReceipt
    }

    enum Result {
        case noChange
        case adopted
        case deferred
    }

    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    private var deferredAdoption: DeferredAdoption?
    private var availabilityObservationID: UUID?

    var hasDeferredAdoption: Bool {
        deferredAdoption != nil
    }

    init(
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger
    ) {
        self.pins = pins
        self.structuralMutations = structuralMutations
        self.profileReferenceAdmission = profileReferenceAdmission
    }

    @discardableResult
    func adoptPendingPins(into profileID: UUID) -> Result {
        guard let admission = profileReferenceAdmission
            .admitReference(to: profileID) else {
            cancelDeferredAdoption()
            return .noChange
        }
        deferredAdoption = DeferredAdoption(
            profileID: profileID,
            admission: admission
        )
        return attemptAdoption()
    }

    func cancelDeferredAdoption() {
        deferredAdoption = nil
        if let availabilityObservationID {
            structuralMutations.cancelAvailabilityObservation(
                availabilityObservationID
            )
            self.availabilityObservationID = nil
        }
    }

    func cancelDeferredAdoption(referencing profileID: UUID) {
        guard deferredAdoption?.profileID == profileID else { return }
        cancelDeferredAdoption()
    }

    func containsReference(to profileID: UUID) -> Bool {
        deferredAdoption?.profileID == profileID
    }

    func drainPendingPins(expecting expected: [ShortcutPin]) -> Bool {
        let expectedIdentities = expected.map(ObjectIdentifier.init)
        guard pins.pendingPinnedWithoutProfileSnapshot()
                .map(ObjectIdentifier.init) == expectedIdentities else {
            return false
        }
        return pins.drainPendingPinnedWithoutProfile()
            .map(ObjectIdentifier.init) == expectedIdentities
    }

    private func attemptAdoption() -> Result {
        guard let deferredAdoption else { return .noChange }
        guard profileReferenceAdmission.validate(
            deferredAdoption.admission
        ) else {
            cancelDeferredAdoption()
            return .noChange
        }
        let profileID = deferredAdoption.profileID
        let pending = pins.pendingPinnedWithoutProfileSnapshot()
        guard pending.isEmpty == false else {
            cancelDeferredAdoption()
            return .noChange
        }
        let profileIDs = Set(
            pending.flatMap {
                [$0.profileId, $0.executionProfileId].compactMap { $0 }
            } + [profileID]
        )
        let lease: ProfileReferenceMutationLease
        do {
            lease = try profileReferenceAdmission.beginReferenceMutation(
                to: profileIDs
            )
        } catch {
            cancelDeferredAdoption()
            return .noChange
        }
        defer {
            precondition(profileReferenceAdmission.endReferenceMutation(lease))
        }
        guard let aggregate = structuralMutations.prepareAggregate() else {
            observeAvailabilityIfNeeded()
            return .deferred
        }
        guard let pendingAdmission = profileReferenceAdmission
            .admitShortcutPinReferences(for: pending),
              profileReferenceAdmission.validate(deferredAdoption.admission),
              profileReferenceAdmission.validate(pendingAdmission) else {
            precondition(aggregate.rollback())
            cancelDeferredAdoption()
            return .noChange
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
        guard profileReferenceAdmission.validate(deferredAdoption.admission),
              profileReferenceAdmission.validate(pendingAdmission) else {
            precondition(aggregate.rollback())
            cancelDeferredAdoption()
            return .noChange
        }
        precondition(aggregate.stage())
        guard profileReferenceAdmission.validate(deferredAdoption.admission),
              profileReferenceAdmission.validate(pendingAdmission) else {
            precondition(aggregate.rollback())
            cancelDeferredAdoption()
            return .noChange
        }
        precondition(aggregate.publish())
        structuralMutations.schedulePersistence()
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
