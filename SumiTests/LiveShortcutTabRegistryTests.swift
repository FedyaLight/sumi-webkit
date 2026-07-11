import Combine
import XCTest

@testable import Sumi

@MainActor
final class LiveShortcutTabRegistryTests: XCTestCase {
    func testRegisterReusesIdenticalSlotAndRefreshesStructuralLookupImmediately() {
        let harness = LiveShortcutRegistryHarness()
        let windowId = UUID()
        let pinId = UUID()
        let tab = makeTab()
        var eventCount = 0
        let cancellable = harness.eventBus.structureChangedPublisher.sink {
            eventCount += 1
        }

        withExtendedLifetime(cancellable) {
            XCTAssertTrue(
                harness.registry.register(tab, for: pinId, in: windowId)
            )
            XCTAssertIdentical(
                harness.registry.tab(for: pinId, in: windowId),
                tab
            )
            XCTAssertIdentical(harness.structuralTab(for: tab.id), tab)
            XCTAssertEqual(eventCount, 1)

            XCTAssertFalse(
                harness.registry.register(tab, for: pinId, in: windowId)
            )
            XCTAssertEqual(eventCount, 1)
        }
    }

    func testRekeyMovesTheSameInstanceAndPublishesOnce() {
        let harness = LiveShortcutRegistryHarness()
        let windowId = UUID()
        let sourcePinId = UUID()
        let targetPinId = UUID()
        let tab = makeTab()
        var eventCount = 0
        let cancellable = harness.eventBus.structureChangedPublisher.sink {
            eventCount += 1
        }
        _ = harness.registry.register(tab, for: sourcePinId, in: windowId)
        eventCount = 0

        withExtendedLifetime(cancellable) {
            XCTAssertTrue(
                harness.registry.rekey(
                    tab,
                    from: sourcePinId,
                    to: targetPinId,
                    in: windowId
                )
            )
            XCTAssertNil(
                harness.registry.tab(for: sourcePinId, in: windowId)
            )
            XCTAssertIdentical(
                harness.registry.tab(for: targetPinId, in: windowId),
                tab
            )
            XCTAssertIdentical(harness.structuralTab(for: tab.id), tab)
            XCTAssertEqual(eventCount, 1)

            XCTAssertFalse(
                harness.registry.rekey(
                    tab,
                    from: sourcePinId,
                    to: targetPinId,
                    in: windowId
                )
            )
            XCTAssertEqual(eventCount, 1)
        }
    }

    func testRemoveAllIsDeterministicPrunesLookupAndCoalescesPublication() {
        let harness = LiveShortcutRegistryHarness()
        let firstWindowId = fixedUUID("00000000-0000-0000-0000-000000000001")
        let secondWindowId = fixedUUID("00000000-0000-0000-0000-000000000002")
        let thirdWindowId = fixedUUID("00000000-0000-0000-0000-000000000003")
        let pinId = UUID()
        let firstTab = makeTab()
        let secondTab = makeTab()
        let thirdTab = makeTab()
        var eventCount = 0
        let cancellable = harness.eventBus.structureChangedPublisher.sink {
            eventCount += 1
        }
        _ = harness.registry.register(thirdTab, for: pinId, in: thirdWindowId)
        _ = harness.registry.register(firstTab, for: pinId, in: firstWindowId)
        _ = harness.registry.register(secondTab, for: pinId, in: secondWindowId)
        eventCount = 0

        let removed = withExtendedLifetime(cancellable) {
            harness.registry.removeAll(
                pinId: pinId,
                excluding: secondWindowId
            )
        }

        XCTAssertEqual(removed.map(\.windowId), [firstWindowId, thirdWindowId])
        XCTAssertIdentical(removed[0].tab, firstTab)
        XCTAssertIdentical(removed[1].tab, thirdTab)
        XCTAssertNil(harness.registry.snapshot[firstWindowId])
        XCTAssertNil(harness.registry.snapshot[thirdWindowId])
        XCTAssertIdentical(
            harness.registry.tab(for: pinId, in: secondWindowId),
            secondTab
        )
        XCTAssertNil(harness.structuralTab(for: firstTab.id))
        XCTAssertIdentical(harness.structuralTab(for: secondTab.id), secondTab)
        XCTAssertNil(harness.structuralTab(for: thirdTab.id))
        XCTAssertEqual(eventCount, 1)
    }

    private func makeTab() -> Tab {
        Tab(loadsCachedFaviconOnInit: false)
    }

    private func fixedUUID(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            XCTFail("Invalid UUID test fixture")
            return UUID()
        }
        return id
    }
}

@MainActor
private final class LiveShortcutRegistryHarness {
    let storage: TabTransientTabRegistryOwner
    let eventBus: TabStructureEventBus
    let coordinator: TabStructuralLookupCoordinator
    let registry: LiveShortcutTabRegistry

    init() {
        let storage = TabTransientTabRegistryOwner()
        let eventBus = TabStructureEventBus()
        let coordinator = TabStructuralLookupCoordinator(
            eventBus: eventBus,
            tabsBySpace: { [:] },
            transientShortcutTabsByWindow: {
                storage.transientShortcutTabsByWindow
            },
            transientExtensionTabsByID: {
                storage.transientExtensionTabsByID
            },
            auxiliaryMiniWindowTabsByID: {
                storage.auxiliaryMiniWindowTabsByID
            }
        )
        self.storage = storage
        self.eventBus = eventBus
        self.coordinator = coordinator
        self.registry = LiveShortcutTabRegistry(
            storage: storage,
            structuralLookup: coordinator
        )
    }

    func structuralTab(for tabId: UUID) -> Tab? {
        coordinator.lookupOwner.tab(
            for: tabId,
            snapshot: TabStructuralLookupSnapshot(
                tabsBySpace: [:],
                transientShortcutTabsByWindow: storage
                    .transientShortcutTabsByWindow,
                transientExtensionTabsByID: storage.transientExtensionTabsByID,
                auxiliaryMiniWindowTabsByID: storage
                    .auxiliaryMiniWindowTabsByID
            )
        )
    }
}
