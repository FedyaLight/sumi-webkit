import Combine
import XCTest

@testable import Sumi

@MainActor
final class TabStructuralLookupCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        changes: PassthroughSubject<Void, Never>
    ) -> TabStructuralLookupCoordinator {
        TabStructuralLookupCoordinator(
            structuralChanges: changes,
            tabsBySpace: { [:] },
            transientShortcutTabsByWindow: { [:] },
            transientExtensionTabsByID: { [:] },
            auxiliaryMiniWindowTabsByID: { [:] }
        )
    }

    func testRequestPublishOutsideTransactionEmitsImmediately() {
        let changes = PassthroughSubject<Void, Never>()
        let coordinator = makeCoordinator(changes: changes)
        var eventCount = 0
        let cancellable = changes.sink { eventCount += 1 }

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
        let changes = PassthroughSubject<Void, Never>()
        let coordinator = makeCoordinator(changes: changes)
        var eventCount = 0
        let cancellable = changes.sink { eventCount += 1 }

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
        let changes = PassthroughSubject<Void, Never>()
        let coordinator = makeCoordinator(changes: changes)
        var eventCount = 0
        let cancellable = changes.sink { eventCount += 1 }

        withExtendedLifetime(cancellable) {
            coordinator.withTransaction {
                _ = coordinator.batchFlushCount
            }
        }

        XCTAssertEqual(eventCount, 0)
    }

    func testNotifyTransientShortcutStateChangedEmitsPublish() {
        let changes = PassthroughSubject<Void, Never>()
        let coordinator = makeCoordinator(changes: changes)
        var eventCount = 0
        let cancellable = changes.sink { eventCount += 1 }

        withExtendedLifetime(cancellable) {
            coordinator.notifyTransientShortcutStateChanged()
        }

        XCTAssertEqual(eventCount, 1)
    }

    func testWithTransactionReturnsOperationValue() {
        let changes = PassthroughSubject<Void, Never>()
        let coordinator = makeCoordinator(changes: changes)

        let result = coordinator.withTransaction { 42 }

        XCTAssertEqual(result, 42)
    }
}
