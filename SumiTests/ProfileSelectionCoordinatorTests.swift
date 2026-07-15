import XCTest

@testable import Sumi

@MainActor
final class ProfileSelectionCoordinatorTests: XCTestCase {
    func testVisibleSelectionOnlyRefreshesVisibility() throws {
        var visibilityUpdates = 0
        let profileID = UUID()
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profileID },
            updateTabVisibility: { visibilityUpdates += 1 }
        )
        let space = Space(name: "Work", profileId: profileID)
        let tab = Tab()
        tab.spaceId = space.id
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [tab],
        ])
        tabManager.selectionStateOwner.replaceCurrentTab(tab)

        makeSelectionCoordinator(tabManager).handleProfileSwitch()

        XCTAssertIdentical(tabManager.selectionStateOwner.currentTab, tab)
        XCTAssertEqual(visibilityUpdates, 1)
        XCTAssertNil(tabManager.structuralPersistence.selectionPersistTask)
    }

    func testInvisibleSelectionChoosesFirstVisibleTabAndPersists() async throws {
        var visibilityUpdates = 0
        let profileID = UUID()
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profileID },
            updateTabVisibility: { visibilityUpdates += 1 }
        )
        let space = Space(name: "Work", profileId: profileID)
        let stale = Tab()
        let visible = Tab()
        visible.spaceId = space.id
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [visible],
        ])
        tabManager.selectionStateOwner.replaceCurrentTab(stale)

        makeSelectionCoordinator(tabManager).handleProfileSwitch()

        XCTAssertIdentical(tabManager.selectionStateOwner.currentTab, visible)
        XCTAssertEqual(visibilityUpdates, 1)
        let persistenceTask = try XCTUnwrap(
            tabManager.structuralPersistence.selectionPersistTask
        )
        await persistenceTask.value
    }

    func testSpaceReconciliationWithoutDefaultProfileIsInert() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = Space(name: "Work", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.structuralPersistence.resetDirtySet()
        tabManager.structuralPersistence.cancelPendingPersistence()

        makeSpaceReconciliationService(tabManager).reconcileIfNeeded()

        XCTAssertNil(space.profileId)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)
    }

    func testSpaceReconciliationAssignsNilProfileAndSchedulesPersistence() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil }
        )
        let space = Space(name: "Work", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.structuralPersistence.resetDirtySet()
        tabManager.structuralPersistence.cancelPendingPersistence()

        makeSpaceReconciliationService(tabManager).reconcileIfNeeded()

        XCTAssertEqual(space.profileId, profileID)
        XCTAssertTrue(
            tabManager.structuralPersistence.dirtySet.dirtySpaceIds
                .contains(space.id)
        )
        XCTAssertNotNil(tabManager.structuralPersistence.scheduledPersistTask)
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    private func makeSelectionCoordinator(
        _ tabManager: TabManager
    ) -> ProfileSelectionCoordinator {
        ProfileSelectionCoordinator(
            selectionContext: TabSelectionContextProjection(
                runtimeConnection: tabManager.runtimePortConnection,
                spaces: tabManager.spaceStateOwner,
                regularTabs: tabManager.regularTabCollectionOwner,
                shortcutPresentation: tabManager.shortcutPresentationOwner
            ),
            selection: tabManager.selectionStateOwner,
            pins: tabManager.shortcutPinCollectionStateOwner,
            runtimeConnection: tabManager.runtimePortConnection,
            persistence: tabManager.structuralPersistence
        )
    }

    private func makeSpaceReconciliationService(
        _ tabManager: TabManager
    ) -> SpaceProfileReconciliationService {
        SpaceProfileReconciliationService(
            spaces: tabManager.spaceStateOwner,
            runtimeConnection: tabManager.runtimePortConnection,
            spaceTransitions: tabManager.profileAssignments.spaces,
            persistence: tabManager.structuralPersistence
        )
    }
}
