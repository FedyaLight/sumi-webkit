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

    func testRestoredLiveSessionsResumeURLAndAutomaticTitleWithoutChangingLauncher()
        throws {
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
            launchURL: try XCTUnwrap(
                URL(string: "https://launcher.example")
            ),
            title: "Launcher"
        )
        browser.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [pin],
            for: space.id
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        let currentURL = try XCTUnwrap(
            URL(string: "https://launcher.example/continued")
        )
        windowState.restorationState.stageShortcutLiveSessions([
            ShortcutLiveSessionSnapshot(
                shortcutPinId: pin.id,
                presentationSpaceId: space.id,
                currentURL: currentURL,
                title: "Continued Work"
            ),
        ])

        WindowSessionShortcutRestorer(
            pins: browser.shortcutPinCollectionStateOwner,
            activation: browser.shortcutPresentationActivation
        ).materializeRestoredLiveSessions(in: windowState)

        let liveTab = try XCTUnwrap(
            browser.liveShortcutTabs.tab(
                for: pin.id,
                in: windowState.id
            )
        )
        XCTAssertEqual(liveTab.url, currentURL)
        XCTAssertEqual(liveTab.name, "Continued Work")
        XCTAssertEqual(pin.launchURL.absoluteString, "https://launcher.example")
        XCTAssertEqual(pin.resolvedDisplayTitle(liveTab: liveTab), "Continued Work")
        XCTAssertTrue(
            windowState.restorationState.pendingShortcutLiveSessions.isEmpty
        )
    }

    func testCustomLauncherTitleWinsOverRestoredPageTitle() throws {
        let liveTab = Tab(
            url: try XCTUnwrap(URL(string: "https://page.example")),
            name: "Page Title"
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: UUID(),
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://launcher.example")),
            title: "My Custom Name",
            titleIsCustom: true
        )

        XCTAssertEqual(
            pin.resolvedDisplayTitle(liveTab: liveTab),
            "My Custom Name"
        )
    }
}
