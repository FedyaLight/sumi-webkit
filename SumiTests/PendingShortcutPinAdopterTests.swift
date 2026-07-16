import Combine
import XCTest

@testable import Sumi

@MainActor
final class PendingShortcutPinAdopterTests: XCTestCase {
    func testNoPendingPinsCreatesNoDeferredWorkOrObservation() throws {
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let revision = tabManager.structuralPersistence.schedulingRevision

        let result = tabManager.lifecycleOwners.pendingShortcutPinAdopter
            .adoptPendingPins(into: UUID())

        guard case .noChange = result else {
            return XCTFail("Empty pending state must need no adoption")
        }
        XCTAssertFalse(
            tabManager.lifecycleOwners.pendingShortcutPinAdopter
                .hasDeferredAdoption
        )
        XCTAssertFalse(
            tabManager.structuralCollectionMutationOwner
                .isAvailabilityObservationActive
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            revision
        )
    }

    func testBusyAggregateRollbackTriggersExactAdoptionOnce() throws {
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let profileID = UUID()
        let pin = makePendingPin()
        install([pin], in: tabManager)
        let aggregate = try XCTUnwrap(
            tabManager.structuralCollectionMutationOwner.prepareAggregate()
        )
        let revision = tabManager.structuralPersistence.schedulingRevision

        let result = tabManager.lifecycleOwners.pendingShortcutPinAdopter
            .adoptPendingPins(into: profileID)

        guard case .deferred = result else {
            return XCTFail("A busy aggregate must defer adoption")
        }
        XCTAssertTrue(
            tabManager.structuralCollectionMutationOwner
                .isAvailabilityObservationActive
        )
        XCTAssertTrue(aggregate.rollback())
        assertAdopted(pin, into: profileID, in: tabManager)
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            revision + 1
        )
        XCTAssertFalse(
            tabManager.structuralCollectionMutationOwner
                .isAvailabilityObservationActive
        )

        let unrelated = try XCTUnwrap(
            tabManager.structuralCollectionMutationOwner.prepareAggregate()
        )
        XCTAssertTrue(unrelated.rollback())
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            revision + 1
        )
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testBusyAggregatePublishTriggersExactAdoptionOnceAfterSettlement() throws {
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let profileID = UUID()
        let unrelatedProfileID = UUID()
        let pin = makePendingPin()
        install([pin], in: tabManager)
        let aggregate = try XCTUnwrap(
            tabManager.structuralCollectionMutationOwner.prepareAggregate()
        )
        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            [],
            for: unrelatedProfileID
        )
        let revision = tabManager.structuralPersistence.schedulingRevision
        guard case .deferred = tabManager.lifecycleOwners
            .pendingShortcutPinAdopter.adoptPendingPins(into: profileID) else {
            return XCTFail("A busy aggregate must defer adoption")
        }

        XCTAssertTrue(aggregate.stage())
        XCTAssertTrue(
            tabManager.structuralCollectionMutationOwner
                .isAvailabilityObservationActive
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().map(\.id),
            [pin.id]
        )
        XCTAssertTrue(aggregate.publish())

        assertAdopted(pin, into: profileID, in: tabManager)
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            revision + 1
        )
        XCTAssertFalse(
            tabManager.lifecycleOwners.pendingShortcutPinAdopter
                .hasDeferredAdoption
        )
        XCTAssertFalse(
            tabManager.structuralCollectionMutationOwner
                .isAvailabilityObservationActive
        )
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testInvalidatedSealedAggregateReleasesDeferredAdoption() throws {
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let profileID = UUID()
        let stagedProfileID = UUID()
        let foreignProfileID = UUID()
        let pin = makePendingPin()
        let stagedPin = makePin(profileID: stagedProfileID)
        let foreignPin = makePin(profileID: foreignProfileID)
        install([pin], in: tabManager)
        let aggregate = try XCTUnwrap(
            tabManager.structuralCollectionMutationOwner.prepareAggregate()
        )
        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            [stagedPin],
            for: stagedProfileID
        )
        guard case .deferred = tabManager.lifecycleOwners
            .pendingShortcutPinAdopter.adoptPendingPins(into: profileID) else {
            return XCTFail("A busy aggregate must defer adoption")
        }
        XCTAssertTrue(aggregate.stage())
        let revision = tabManager.structuralPersistence.schedulingRevision

        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            [foreignPin],
            for: foreignProfileID
        )
        XCTAssertFalse(aggregate.publish())

        assertAdopted(pin, into: profileID, in: tabManager)
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: foreignProfileID).map(\.id),
            [foreignPin.id]
        )
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: stagedProfileID).isEmpty
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            revision + 1
        )
        XCTAssertFalse(
            tabManager.structuralCollectionMutationOwner
                .isAvailabilityObservationActive
        )
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testCancelRemovesDeferredWorkAndLeavesPendingPinsUntouched() throws {
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let pin = makePendingPin()
        install([pin], in: tabManager)
        let aggregate = try XCTUnwrap(
            tabManager.structuralCollectionMutationOwner.prepareAggregate()
        )
        guard case .deferred = tabManager.lifecycleOwners
            .pendingShortcutPinAdopter.adoptPendingPins(into: UUID()) else {
            return XCTFail("A busy aggregate must defer adoption")
        }

        tabManager.lifecycleOwners.pendingShortcutPinAdopter
            .cancelDeferredAdoption()
        XCTAssertTrue(aggregate.rollback())

        XCTAssertFalse(
            tabManager.structuralCollectionMutationOwner
                .isAvailabilityObservationActive
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().map(\.id),
            [pin.id]
        )
    }

    func testImmediateAdoptionPublishesAndSchedulesExactlyOnce() throws {
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let profileID = UUID()
        let pin = makePendingPin()
        install([pin], in: tabManager)
        var publicationCount = 0
        var observedPendingCount: Int?
        var observedDestinationIDs: [UUID]?
        let observation = tabManager.objectWillChange.sink {
            publicationCount += 1
            observedPendingCount = tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().count
            observedDestinationIDs = tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: profileID).map(\.id)
        }
        let revision = tabManager.structuralPersistence.schedulingRevision

        let result = tabManager.lifecycleOwners.pendingShortcutPinAdopter
            .adoptPendingPins(into: profileID)

        guard case .adopted = result else {
            return XCTFail("Available structure must adopt synchronously")
        }
        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(observedPendingCount, 0)
        XCTAssertEqual(observedDestinationIDs, [pin.id])
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            revision + 1
        )
        assertAdopted(pin, into: profileID, in: tabManager)
        XCTAssertFalse(
            tabManager.structuralCollectionMutationOwner
                .isAvailabilityObservationActive
        )
        withExtendedLifetime(observation) {}
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testAggregateRollbackRestoresExactPendingAndDestinationPins() throws {
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let profileID = UUID()
        let existing = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://existing.example")!,
            title: "Existing"
        )
        let pending = makePendingPin()
        tabManager.shortcutPinCollectionStateOwner.replaceAll(
            pinnedByProfile: [profileID: [existing]],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [pending]
        )
        let aggregate = try XCTUnwrap(
            tabManager.structuralCollectionMutationOwner.prepareAggregate()
        )

        let drained = tabManager.shortcutPinCollectionStateOwner
            .drainPendingPinnedWithoutProfile()
        tabManager.shortcutPinStoreOwner.withPinnedArray(for: profileID) {
            $0.append(contentsOf: drained)
        }
        XCTAssertTrue(aggregate.rollback())

        let restoredPending = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().first
        )
        let restoredExisting = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: profileID).first
        )
        XCTAssertIdentical(restoredPending, pending)
        XCTAssertIdentical(restoredExisting, existing)
    }

    private func install(_ pins: [ShortcutPin], in tabManager: TabManager) {
        tabManager.shortcutPinCollectionStateOwner.replaceAll(
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: pins
        )
    }

    private func assertAdopted(
        _ pin: ShortcutPin,
        into profileID: UUID,
        in tabManager: TabManager
    ) {
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().isEmpty
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: profileID).map(\.id),
            [pin.id]
        )
    }

    private func makePendingPin() -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://pending.example")!,
            title: "Pending"
        )
    }

    private func makePin(profileID: UUID) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://profile.example")!,
            title: "Profile"
        )
    }
}
