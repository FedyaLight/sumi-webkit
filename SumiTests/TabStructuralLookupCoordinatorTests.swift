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

    func testNotifyTransientShortcutStateChangedEmitsExactPagePublish() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)
        let windowID = UUID()
        let pinID = UUID()
        let spaceID = UUID()
        let profileID = UUID()
        let tab = Tab(spaceId: spaceID, loadsCachedFaviconOnInit: false)
        tab.profileId = profileID
        var scopes: [TabStructureChangeScope] = []
        let cancellable = eventBus.scopedStructureChangesPublisher.sink {
            scopes.append($0)
        }

        withExtendedLifetime(cancellable) {
            coordinator.notifyTransientShortcutStateChanged(
                entries: [
                    LiveShortcutTabEntry(
                        windowId: windowID,
                        pinId: pinID,
                        tab: tab
                    ),
                ]
            )
        }

        XCTAssertEqual(
            scopes,
            [
                TabStructureChangeScope.liveShortcut(
                    windowID: windowID,
                    spaceID: spaceID,
                    profileID: profileID
                ),
            ]
        )
    }

    func testNestedTransactionMergesTypedSidebarScopes() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)
        let spaceID = UUID()
        let profileID = UUID()
        var scopes: [TabStructureChangeScope] = []
        let cancellable = eventBus.scopedStructureChangesPublisher.sink {
            scopes.append($0)
        }

        coordinator.withTransaction {
            coordinator.requestPublish(scope: .space(spaceID))
            coordinator.withTransaction {
                coordinator.requestPublish(scope: .profile(profileID))
            }
        }

        XCTAssertEqual(
            scopes,
            [
                TabStructureChangeScope(
                    affectedSpaceIDs: [spaceID],
                    affectedProfileIDs: [profileID],
                    affectsSpaceCatalog: false,
                    affectsAllPages: false
                ),
            ]
        )
        withExtendedLifetime(cancellable) {}
    }

    func testWithTransactionReturnsOperationValue() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)

        let result = coordinator.withTransaction { 42 }

        XCTAssertEqual(result, 42)
    }
}
