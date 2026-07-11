import XCTest

@testable import Sumi

@MainActor
final class SpaceProfileRuntimeStateServiceTests: XCTestCase {
    func testReconcileUsesLiveContentAndFocusedShortcutSelection() throws {
        let tabManager = try makeInMemoryTabManager()
        let focusedSpace = tabManager.spaceServices.catalog.createSpace(name: "Focused")
        let loadedSpace = tabManager.spaceServices.catalog.createSpace(name: "Loaded")
        let selectedShortcutSpace = tabManager.spaceServices.catalog
            .createSpace(name: "Selected shortcut")
        let staticStructureOnlySpace = tabManager.spaceServices.catalog
            .createSpace(name: "Static structure")

        _ = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://focused.example",
            in: focusedSpace,
            activate: false
        )
        _ = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://loaded.example",
            in: loadedSpace,
            activate: false
        )
        _ = tabManager.folderMutationOwner.createFolder(
            for: staticStructureOnlySpace.id,
            name: "Persisted folder"
        )

        tabManager.profileRuntimeState.reconcile(
            focusedSpaceId: focusedSpace.id,
            selectedShortcutSpaceIds: [selectedShortcutSpace.id]
        )

        XCTAssertEqual(focusedSpace.profileRuntimeState, .active)
        XCTAssertEqual(loadedSpace.profileRuntimeState, .loadedInactive)
        XCTAssertEqual(selectedShortcutSpace.profileRuntimeState, .loadedInactive)
        XCTAssertEqual(staticStructureOnlySpace.profileRuntimeState, .dormant)
    }
}
