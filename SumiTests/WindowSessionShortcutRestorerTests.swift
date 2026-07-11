import XCTest

@testable import Sumi

@MainActor
final class WindowSessionShortcutRestorerTests: XCTestCase {
    func testMaterializedPinCanonicalizesMismatchedSavedRole() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://restore.example")),
            title: "Restore"
        )
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [pin],
            for: space.id
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = .essential

        let didMaterialize = WindowSessionShortcutRestorer(
            tabManager: tabManager
        ).materializeSelectionIfNeeded(in: windowState)

        XCTAssertTrue(didMaterialize)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .spacePinned)
        XCTAssertNotNil(
            tabManager.liveShortcutTabs.tab(
                for: pin.id,
                in: windowState.id
            )
        )
    }

    func testRoleWithoutPinIdentityIsCleared() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentShortcutPinRole = .essential

        let didMaterialize = WindowSessionShortcutRestorer(
            tabManager: tabManager
        ).materializeSelectionIfNeeded(in: windowState)

        XCTAssertFalse(didMaterialize)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
    }
}
