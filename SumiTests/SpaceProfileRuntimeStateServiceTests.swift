import XCTest

@testable import Sumi

@MainActor
final class SpaceProfileRuntimeStateServiceTests: XCTestCase {
    func testReconcileUsesLiveContentAndFocusedShortcutSelection() throws {
        let focusedSpace = Space(name: "Focused")
        let loadedSpace = Space(name: "Loaded")
        let selectedShortcutSpace = Space(name: "Selected shortcut")
        let staticStructureOnlySpace = Space(name: "Static structure")
        let fixture = Fixture(
            spaces: [
                focusedSpace, loadedSpace, selectedShortcutSpace,
                staticStructureOnlySpace,
            ],
            liveTabsBySpace: [focusedSpace.id, loadedSpace.id]
        )

        fixture.service.reconcile(
            focusedSpaceId: focusedSpace.id,
            selectedShortcutSpaceIds: [selectedShortcutSpace.id]
        )

        XCTAssertEqual(focusedSpace.profileRuntimeState, .active)
        XCTAssertEqual(loadedSpace.profileRuntimeState, .loadedInactive)
        XCTAssertEqual(selectedShortcutSpace.profileRuntimeState, .loadedInactive)
        XCTAssertEqual(staticStructureOnlySpace.profileRuntimeState, .dormant)
    }

    @MainActor
    private final class Fixture {
        let service: SpaceProfileRuntimeStateService

        init(spaces: [Space], liveTabsBySpace: [UUID]) {
            let spaceState = TabSpaceCollectionStateOwner()
            spaceState.replaceSpaces(spaces)
            let regularTabs = RegularTabCollectionStateOwner()
            regularTabs.replaceTabsBySpace(Dictionary(
                uniqueKeysWithValues: liveTabsBySpace.map { spaceID in
                    (
                        spaceID,
                        [Tab(
                            url: URL(string: "https://runtime.example")!,
                            spaceId: spaceID,
                            loadsCachedFaviconOnInit: false
                        )]
                    )
                }
            ))
            service = SpaceProfileRuntimeStateService(
                spaces: spaceState,
                regularTabs: regularTabs,
                liveShortcutTabs: TabTransientTabRegistryOwner()
            )
        }
    }
}
