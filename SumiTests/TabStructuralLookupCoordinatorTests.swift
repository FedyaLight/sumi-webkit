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
            stateStore: TabStateStore()
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

    func testNotifyTransientShortcutStateChangedSeparatesRuntimeAndPageResidence() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)
        let windowID = UUID()
        let pinID = UUID()
        let spaceID = UUID()
        let profileID = UUID()
        let tab = Tab(spaceId: spaceID, loadsCachedFaviconOnInit: false)
        tab.profileId = profileID
        var scopes: [TabStructureChangeScope] = []
        var pages: [LivePageResidenceScope] = []
        let structuralCancellable = eventBus.scopedStructureChangesPublisher.sink {
            scopes.append($0)
        }
        let residenceCancellable = eventBus.livePageResidenceChangesPublisher
            .sink { pages.append($0) }

        withExtendedLifetime((structuralCancellable, residenceCancellable)) {
            coordinator.notifyTransientShortcutStateChanged(
                entries: [
                    LiveShortcutTabEntry(
                        windowId: windowID,
                        pinId: pinID,
                        tab: tab,
                        presentationPage: LiveShortcutPresentationPageReceipt(
                            windowID: windowID,
                            spaceID: spaceID,
                            profileID: profileID
                        )
                    ),
                ]
            )
        }

        XCTAssertEqual(
            scopes,
            [.runtimeOnly]
        )
        XCTAssertEqual(
            pages,
            [LivePageResidenceScope(
                windowID: windowID,
                spaceID: spaceID
            )]
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

    func testNestedTransactionCoalescesDuplicateLivePageResidenceScopes() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)
        let windowID = UUID()
        let profileID = UUID()
        let firstPage = TabStructurePageScope(
            windowID: windowID,
            spaceID: UUID(),
            profileID: profileID
        )
        let secondPage = TabStructurePageScope(
            windowID: windowID,
            spaceID: UUID(),
            profileID: profileID
        )
        func entry(_ page: TabStructurePageScope) -> LiveShortcutTabEntry {
            LiveShortcutTabEntry(
                windowId: windowID,
                pinId: UUID(),
                tab: Tab(loadsCachedFaviconOnInit: false),
                presentationPage: LiveShortcutPresentationPageReceipt(
                    windowID: page.windowID,
                    spaceID: page.spaceID,
                    profileID: page.profileID
                )
            )
        }
        var structuralScopes: [TabStructureChangeScope] = []
        var residencePages: [LivePageResidenceScope] = []
        let structuralCancellable = eventBus.scopedStructureChangesPublisher
            .sink { structuralScopes.append($0) }
        let residenceCancellable = eventBus.livePageResidenceChangesPublisher
            .sink { residencePages.append($0) }

        coordinator.withTransaction {
            coordinator.notifyTransientShortcutStateChanged(
                entries: [entry(firstPage), entry(firstPage)]
            )
            coordinator.withTransaction {
                coordinator.notifyTransientShortcutStateChanged(
                    entries: [entry(secondPage)]
                )
            }
        }

        XCTAssertEqual(structuralScopes, [.runtimeOnly])
        XCTAssertEqual(
            Set(residencePages),
            Set([
                LivePageResidenceScope(
                    windowID: firstPage.windowID,
                    spaceID: firstPage.spaceID
                ),
                LivePageResidenceScope(
                    windowID: secondPage.windowID,
                    spaceID: secondPage.spaceID
                ),
            ])
        )
        XCTAssertEqual(residencePages.count, 2)
        withExtendedLifetime((structuralCancellable, residenceCancellable)) {}
    }

    func testWithTransactionReturnsOperationValue() {
        let eventBus = TabStructureEventBus()
        let coordinator = makeCoordinator(eventBus: eventBus)

        let result = coordinator.withTransaction { 42 }

        XCTAssertEqual(result, 42)
    }
}
