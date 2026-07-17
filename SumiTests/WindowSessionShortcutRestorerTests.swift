import XCTest

@testable import Sumi

@MainActor
final class WindowSessionShortcutRestorerTests: XCTestCase {
    func testMaterializedPinCanonicalizesMismatchedSavedRole() throws {
        let browser = BrowserManager()
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Space",
                icon: "square",
                profileID: nil
            )
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://restore.example")),
            title: "Restore"
        )
        browser.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [pin],
            for: space.id
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = .essential

        let didMaterialize = WindowSessionShortcutRestorer(
            pins: browser.shortcutPinCollectionStateOwner,
            activation: browser.shortcutPresentationActivation
        ).materializeSelectionIfNeeded(in: windowState)

        XCTAssertTrue(didMaterialize)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .spacePinned)
        XCTAssertNotNil(
            browser.liveShortcutTabs.tab(
                for: pin.id,
                in: windowState.id
            )
        )
    }

    func testRoleWithoutPinIdentityIsCleared() throws {
        let browser = BrowserManager()
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Space",
                icon: "square",
                profileID: nil
            )
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentShortcutPinRole = .essential

        let didMaterialize = WindowSessionShortcutRestorer(
            pins: browser.shortcutPinCollectionStateOwner,
            activation: browser.shortcutPresentationActivation
        ).materializeSelectionIfNeeded(in: windowState)

        XCTAssertFalse(didMaterialize)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
    }
}
