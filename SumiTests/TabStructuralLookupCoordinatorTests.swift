import Combine
import XCTest

@testable import Sumi

@MainActor
final class TabStructuralLookupCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        eventBus: TabStructureEventBus
    ) -> TabStructuralLookupCoordinator {
        TabStructuralLookupCoordinator(
            eventBus: eventBus,
            tabsBySpace: { [:] },
            transientShortcutTabsByWindow: { [:] },
            transientExtensionTabsByID: { [:] },
            auxiliaryMiniWindowTabsByID: { [:] }
        )
    }

    func testRequestPublishOutsideTransactionEmitsImmediately() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)
        var eventCount = 0
        let cancellable = eventBus.structureChangedPublisher.sink { eventCount += 1 }

        withExtendedLifetime(cancellable) {
            coordinator.requestPublish()
        }

        XCTAssertEqual(eventCount, 1)
    }

    // Coalescing of the *lookup batch* flush count per outermost transaction is covered at
    // the integration level in TabManagerStructuralBatchingTests (which queues real lookup
    // entries). Here we assert the coordinator's own contract: nested transactions publish
    // exactly once, on outermost exit, with nothing emitted while still batching.
    func testNestedTransactionCoalescesPublishToExactlyOneEmission() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)
        var eventCount = 0
        let cancellable = eventBus.structureChangedPublisher.sink { eventCount += 1 }

        withExtendedLifetime(cancellable) {
            coordinator.withTransaction {
                coordinator.requestPublish()
                coordinator.withTransaction {
                    coordinator.requestPublish()
                }
                // Still batching: nothing published yet.
                XCTAssertEqual(eventCount, 0)
            }
        }

        XCTAssertEqual(eventCount, 1, "Nested transactions must publish exactly once on outermost exit")
    }

    func testTransactionWithoutPublishRequestDoesNotEmit() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)
        var eventCount = 0
        let cancellable = eventBus.structureChangedPublisher.sink { eventCount += 1 }

        withExtendedLifetime(cancellable) {
            coordinator.withTransaction {
                _ = coordinator.batchFlushCount
            }
        }

        XCTAssertEqual(eventCount, 0)
    }

    func testNotifyTransientShortcutStateChangedEmitsPublish() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)
        var eventCount = 0
        let cancellable = eventBus.structureChangedPublisher.sink { eventCount += 1 }

        withExtendedLifetime(cancellable) {
            coordinator.notifyTransientShortcutStateChanged()
        }

        XCTAssertEqual(eventCount, 1)
    }

    func testWithTransactionReturnsOperationValue() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)

        let result = coordinator.withTransaction { 42 }

        XCTAssertEqual(result, 42)
    }
}
