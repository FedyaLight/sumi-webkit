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
                harness.register(tab, for: pinId, in: windowId)
            )
            XCTAssertIdentical(
                harness.registry.tab(for: pinId, in: windowId),
                tab
            )
            XCTAssertIdentical(harness.structuralTab(for: tab.id), tab)
            XCTAssertEqual(eventCount, 1)

            XCTAssertFalse(
                harness.register(tab, for: pinId, in: windowId)
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
        let profileID = UUID()
        let presentationPage = harness.page(
            in: windowId,
            spaceID: UUID(),
            profileID: profileID
        )
        var scopes: [TabStructureChangeScope] = []
        let cancellable = harness.eventBus.scopedStructureChangesPublisher.sink {
            scopes.append($0)
        }
        _ = harness.registry.register(
            tab,
            for: sourcePinId,
            in: windowId,
            presentationPage: presentationPage
        )
        scopes = []

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
            XCTAssertEqual(
                harness.registry.entry(containing: tab)?.presentationPage,
                presentationPage
            )
            XCTAssertEqual(scopes, [.page(presentationPage.page)])

            XCTAssertFalse(
                harness.registry.rekey(
                    tab,
                    from: sourcePinId,
                    to: targetPinId,
                    in: windowId
                )
            )
            XCTAssertEqual(scopes, [.page(presentationPage.page)])
        }
    }

    func testRekeyRejectsOccupiedTargetWithoutMutationOrPublication() {
        let harness = LiveShortcutRegistryHarness()
        let windowID = UUID()
        let sourcePinID = UUID()
        let targetPinID = UUID()
        let sourceTab = makeTab()
        let targetTab = makeTab()
        var eventCount = 0
        let cancellable = harness.eventBus.structureChangedPublisher.sink {
            eventCount += 1
        }
        _ = harness.register(sourceTab, for: sourcePinID, in: windowID)
        _ = harness.register(targetTab, for: targetPinID, in: windowID)
        eventCount = 0

        XCTAssertFalse(harness.registry.rekey(
            sourceTab,
            from: sourcePinID,
            to: targetPinID,
            in: windowID
        ))
        XCTAssertIdentical(
            harness.registry.tab(for: sourcePinID, in: windowID),
            sourceTab
        )
        XCTAssertIdentical(
            harness.registry.tab(for: targetPinID, in: windowID),
            targetTab
        )
        XCTAssertEqual(eventCount, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testRelocationPublishesExactSourceAndTargetAndRetirementRetainsTarget() {
        let harness = LiveShortcutRegistryHarness()
        let windowID = UUID()
        let pinID = UUID()
        let profileID = UUID()
        let sourcePage = harness.page(
            in: windowID,
            spaceID: UUID(),
            profileID: profileID
        )
        let targetPage = harness.page(
            in: windowID,
            spaceID: UUID(),
            profileID: profileID
        )
        let unrelatedPage = TabStructurePageScope(
            windowID: windowID,
            spaceID: UUID(),
            profileID: profileID
        )
        let tab = makeTab()
        var scopes: [TabStructureChangeScope] = []
        let cancellable = harness.eventBus.scopedStructureChangesPublisher.sink {
            scopes.append($0)
        }
        _ = harness.registry.register(
            tab,
            for: pinID,
            in: windowID,
            presentationPage: sourcePage
        )
        scopes = []

        XCTAssertTrue(
            harness.registry.relocate(
                tab,
                from: pinID,
                to: pinID,
                in: windowID,
                presentationPage: targetPage
            )
        )
        XCTAssertEqual(scopes.count, 1)
        XCTAssertEqual(
            scopes[0].affectedPages,
            Set([sourcePage.page, targetPage.page])
        )
        XCTAssertFalse(
            scopes[0].affectsPage(
                windowID: unrelatedPage.windowID,
                spaceID: unrelatedPage.spaceID,
                profileID: unrelatedPage.profileID
            )
        )
        XCTAssertEqual(
            harness.registry.entry(containing: tab)?.presentationPage,
            targetPage
        )

        scopes = []
        XCTAssertIdentical(
            harness.registry.remove(pinId: pinID, in: windowID)?.tab,
            tab
        )
        XCTAssertEqual(scopes, [.page(targetPage.page)])
        withExtendedLifetime(cancellable) {}
    }

    func testRelocationRejectsOccupiedTargetWithoutMutationOrPublication() {
        let harness = LiveShortcutRegistryHarness()
        let windowID = UUID()
        let sourcePinID = UUID()
        let targetPinID = UUID()
        let sourceTab = makeTab()
        let targetTab = makeTab()
        let sourcePage = harness.page(
            in: windowID,
            spaceID: UUID(),
            profileID: UUID()
        )
        let targetPage = harness.page(
            in: windowID,
            spaceID: UUID(),
            profileID: UUID()
        )
        var eventCount = 0
        let cancellable = harness.eventBus.structureChangedPublisher.sink {
            eventCount += 1
        }
        _ = harness.registry.register(
            sourceTab,
            for: sourcePinID,
            in: windowID,
            presentationPage: sourcePage
        )
        _ = harness.registry.register(
            targetTab,
            for: targetPinID,
            in: windowID,
            presentationPage: targetPage
        )
        eventCount = 0

        XCTAssertFalse(harness.registry.relocate(
            sourceTab,
            from: sourcePinID,
            to: targetPinID,
            in: windowID,
            presentationPage: targetPage
        ))
        XCTAssertEqual(
            harness.registry.entry(containing: sourceTab)?.presentationPage,
            sourcePage
        )
        XCTAssertIdentical(
            harness.registry.tab(for: targetPinID, in: windowID),
            targetTab
        )
        XCTAssertEqual(eventCount, 0)
        withExtendedLifetime(cancellable) {}
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
        _ = harness.register(thirdTab, for: pinId, in: thirdWindowId)
        _ = harness.register(firstTab, for: pinId, in: firstWindowId)
        _ = harness.register(secondTab, for: pinId, in: secondWindowId)
        eventCount = 0

        let removed = withExtendedLifetime(cancellable) {
            harness.batchRetirement.remove(pinIDs: [pinId])
        }

        XCTAssertEqual(
            removed.map(\.windowId),
            [firstWindowId, secondWindowId, thirdWindowId]
        )
        XCTAssertIdentical(removed[0].tab, firstTab)
        XCTAssertIdentical(removed[1].tab, secondTab)
        XCTAssertIdentical(removed[2].tab, thirdTab)
        XCTAssertNil(harness.registry.snapshot[firstWindowId])
        XCTAssertNil(harness.registry.snapshot[secondWindowId])
        XCTAssertNil(harness.registry.snapshot[thirdWindowId])
        XCTAssertNil(harness.structuralTab(for: firstTab.id))
        XCTAssertNil(harness.structuralTab(for: secondTab.id))
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
    let batchRetirement: LiveShortcutTabBatchRetirement
    private var pageSpaceByWindow: [UUID: UUID] = [:]

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
        self.batchRetirement = LiveShortcutTabBatchRetirement(
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

    func register(_ tab: Tab, for pinId: UUID, in windowId: UUID) -> Bool {
        registry.register(
            tab,
            for: pinId,
            in: windowId,
            presentationPage: page(in: windowId)
        )
    }

    func page(in windowId: UUID) -> LiveShortcutPresentationPageReceipt {
        let spaceID = pageSpaceByWindow[windowId] ?? UUID()
        pageSpaceByWindow[windowId] = spaceID
        return page(
            in: windowId,
            spaceID: spaceID,
            profileID: nil
        )
    }

    func page(
        in windowId: UUID,
        spaceID: UUID,
        profileID: UUID?
    ) -> LiveShortcutPresentationPageReceipt {
        LiveShortcutPresentationPageReceipt(
            windowID: windowId,
            spaceID: spaceID,
            profileID: profileID
        )
    }
}
