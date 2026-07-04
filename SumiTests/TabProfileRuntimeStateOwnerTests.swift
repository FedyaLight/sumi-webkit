import XCTest

@testable import Sumi

@MainActor
final class TabProfileRuntimeStateOwnerTests: XCTestCase {
    func testReconcileMarksActiveLoadedInactiveAndDormantSpaces() throws {
        let tabManager = try makeInMemoryTabManager()
        let activeSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Active")
        let loadedInactiveSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Loaded")
        let dormantSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Dormant")

        _ = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://active.example",
            in: activeSpace,
            activate: false
        )
        _ = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://loaded.example",
            in: loadedInactiveSpace,
            activate: false
        )

        tabManager.profileRuntimeStateOwner.reconcile(activeSpaceId: activeSpace.id)

        XCTAssertEqual(activeSpace.profileRuntimeState, .active)
        XCTAssertEqual(loadedInactiveSpace.profileRuntimeState, .loadedInactive)
        XCTAssertEqual(dormantSpace.profileRuntimeState, .dormant)
    }
}
