import XCTest

@testable import Sumi

@MainActor
final class ProfileSelectionCoordinatorTests: XCTestCase {
    func testVisibleSelectionOnlyRefreshesVisibility() throws {
        var visibilityUpdates = 0
        let profileID = UUID()
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            currentProfileId: { profileID },
            updateTabVisibility: { visibilityUpdates += 1 }
        ))
        let space = Space(name: "Work", profileId: profileID)
        let tab = Tab()
        tab.spaceId = space.id
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            space.id: [tab],
        ])
        tabManager.tabStateStore.selection.replaceCurrentTab(tab)

        makeSelectionCoordinator(tabManager).handleProfileSwitch()

        XCTAssertIdentical(tabManager.tabStateStore.selection.currentTab, tab)
        XCTAssertEqual(visibilityUpdates, 1)
        XCTAssertNil(tabManager.structuralPersistence.selectionPersistTask)
    }

    func testInvisibleSelectionChoosesFirstVisibleTabAndPersists() async throws {
        var visibilityUpdates = 0
        let profileID = UUID()
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            currentProfileId: { profileID },
            updateTabVisibility: { visibilityUpdates += 1 }
        ))
        let space = Space(name: "Work", profileId: profileID)
        let stale = Tab()
        let visible = Tab()
        visible.spaceId = space.id
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            space.id: [visible],
        ])
        tabManager.tabStateStore.selection.replaceCurrentTab(stale)

        makeSelectionCoordinator(tabManager).handleProfileSwitch()

        XCTAssertIdentical(tabManager.tabStateStore.selection.currentTab, visible)
        XCTAssertEqual(visibilityUpdates, 1)
        let persistenceTask = try XCTUnwrap(
            tabManager.structuralPersistence.selectionPersistTask
        )
        await persistenceTask.value
    }

    func testSpaceReconciliationWithoutDefaultProfileIsInert() throws {
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make())
        let space = Space(name: "Work", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.structuralPersistence.resetDirtySet()
        tabManager.structuralPersistence.cancelPendingPersistence()

        let result = makeSpaceReconciliationService(tabManager).startNext(
            using: tabManager.runtimePortConnection.captureLease(),
            completion: { _ in
                XCTFail("No-profile reconciliation must not defer")
            }
        )

        guard case .completed(.unavailable) = result else {
            return XCTFail("Missing default profile must remain unavailable")
        }
        XCTAssertNil(space.profileId)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)
    }

    func testSpaceReconciliationAssignsNilProfileAndSchedulesPersistence() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil }
        ))
        let space = Space(name: "Work", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.structuralPersistence.resetDirtySet()
        tabManager.structuralPersistence.cancelPendingPersistence()

        let result = makeSpaceReconciliationService(tabManager).startNext(
            using: tabManager.runtimePortConnection.captureLease(),
            completion: { _ in
                XCTFail("Model-only reconciliation must not defer")
            }
        )

        guard case .completed(.committed) = result else {
            return XCTFail("Model-only reconciliation must commit")
        }
        XCTAssertEqual(space.profileId, profileID)
        XCTAssertTrue(
            tabManager.structuralPersistence.dirtySet.dirtySpaceIds
                .contains(space.id)
        )
        XCTAssertNotNil(tabManager.structuralPersistence.scheduledPersistTask)
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    private func makeSelectionCoordinator(
        _ tabManager: BrowserManager
    ) -> ProfileSelectionCoordinator {
        ProfileSelectionCoordinator(
            selectionContext: TabSelectionContextProjection(
                runtimeConnection: tabManager.runtimePortConnection,
                spaces: tabManager.spaceStateOwner,
                regularTabs: tabManager.regularTabCollectionOwner,
                shortcutPresentation: tabManager.shortcutPresentationOwner
            ),
            selection: tabManager.tabStateStore.selection,
            pins: tabManager.shortcutPinCollectionStateOwner,
            runtimeConnection: tabManager.runtimePortConnection,
            persistence: tabManager.structuralPersistence
        )
    }

    private func makeSpaceReconciliationService(
        _ tabManager: BrowserManager
    ) -> SpaceProfileReconciliationService {
        SpaceProfileReconciliationService(
            spaces: tabManager.spaceStateOwner,
            runtimeConnection: tabManager.runtimePortConnection,
            spaceTransitions: tabManager.spaceProfileTransitions,
            transitionLifecycle: tabManager.spaceProfileTransitions.lifecycle
        )
    }
}
