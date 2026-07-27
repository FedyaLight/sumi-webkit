@testable import Sumi
import XCTest

@MainActor
final class SumiProfileRoutingTests: XCTestCase {
    func testAdoptProfileIfNeededRepairsUnknownWindowProfileId() throws {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        let currentProfile = try XCTUnwrap(browserManager.currentProfile)

        let windowState = BrowserWindowState()
        windowState.currentProfileId = UUID()
        registry.register(windowState)

        browserManager.adoptProfileIfNeeded(
            for: windowState,
            context: .windowActivation
        )

        XCTAssertEqual(windowState.currentProfileId, currentProfile.id)
        XCTAssertEqual(browserManager.currentProfile?.id, currentProfile.id)
    }

    func testWindowActivationSwitchUpdatesActiveRequestedWindow() async throws {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        let currentProfile = try XCTUnwrap(browserManager.currentProfile)
        let targetProfile = try browserManager.profileManager.createProfile(
            name: "Target"
        )
        let currentSpace = Space(name: "Current", profileId: currentProfile.id)
        let targetSpace = Space(name: "Target", profileId: targetProfile.id)
        browserManager.spaceStateOwner.replaceSpaces([currentSpace, targetSpace])
        browserManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let requestedWindow = BrowserWindowState()
        let activeWindow = BrowserWindowState()
        requestedWindow.currentProfileId = currentProfile.id
        requestedWindow.currentSpaceId = targetSpace.id
        activeWindow.currentProfileId = currentProfile.id
        activeWindow.currentSpaceId = currentSpace.id

        registry.register(requestedWindow)
        registry.register(activeWindow)
        registry.setActive(requestedWindow)

        await browserManager.switchToProfile(
            targetProfile,
            context: .windowActivation,
            in: requestedWindow
        )

        XCTAssertEqual(requestedWindow.currentProfileId, targetProfile.id)
        XCTAssertEqual(activeWindow.currentProfileId, currentProfile.id)
        XCTAssertEqual(browserManager.currentProfile?.id, targetProfile.id)
    }

    func testWindowActivationSwitchIgnoresInactiveRequestedWindow() async throws {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        let currentProfile = try XCTUnwrap(browserManager.currentProfile)
        let targetProfile = Profile(name: "Target")
        browserManager.profileManager.profiles = [currentProfile, targetProfile]
        let currentSpace = Space(name: "Current", profileId: currentProfile.id)
        let targetSpace = Space(name: "Target", profileId: targetProfile.id)
        browserManager.spaceStateOwner.replaceSpaces([currentSpace, targetSpace])
        browserManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let requestedWindow = BrowserWindowState()
        let activeWindow = BrowserWindowState()
        requestedWindow.currentProfileId = currentProfile.id
        requestedWindow.currentSpaceId = targetSpace.id
        activeWindow.currentProfileId = currentProfile.id
        activeWindow.currentSpaceId = currentSpace.id

        registry.register(requestedWindow)
        registry.register(activeWindow)
        registry.setActive(activeWindow)

        await browserManager.switchToProfile(
            targetProfile,
            context: .windowActivation,
            in: requestedWindow
        )

        XCTAssertEqual(requestedWindow.currentProfileId, currentProfile.id)
        XCTAssertEqual(activeWindow.currentProfileId, currentProfile.id)
        XCTAssertEqual(browserManager.currentProfile?.id, currentProfile.id)
    }

    func testProfileSwitchRejectsReservedTarget() async throws {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        let currentProfile = try XCTUnwrap(browserManager.currentProfile)
        let targetProfile = try browserManager.profileManager.createProfile(
            name: "Target"
        )
        let window = BrowserWindowState()
        window.currentProfileId = currentProfile.id
        registry.register(window)
        registry.setActive(window)
        _ = try browserManager.profileReferenceAdmission.reserve(
            profile: targetProfile,
            fallbackID: currentProfile.id
        )

        await browserManager.switchToProfile(
            targetProfile,
            context: .userInitiated,
            in: window
        )

        XCTAssertEqual(browserManager.currentProfile?.id, currentProfile.id)
        XCTAssertEqual(window.currentProfileId, currentProfile.id)
    }

    private func makeInMemoryStartupContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }
}
