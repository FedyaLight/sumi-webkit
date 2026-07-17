import XCTest

@testable import Sumi

@MainActor
final class SidebarPinCommandIdentityTests: XCTestCase {
    func testExecutionProfileRejectsReplacedPinWithSameIdentity() throws {
        let browser = try makeBrowser()
        defer { browser.tabRuntimeLifecycle.shutdown() }
        let profile = Profile(name: "Execution")
        let space = Space(name: "Work", profileId: profile.id)
        let (stale, replacement) = makePinPair(spaceID: space.id)
        browser.profileManager.profiles = [profile]
        browser.spaceStateOwner.replaceSpaces([space])
        install(replacement, in: browser, spaceID: space.id)

        XCTAssertFalse(
            makeExecutionCommands(browser: browser)
                .assignExecutionProfile(stale, profileID: profile.id)
        )
        XCTAssertNil(replacement.executionProfileId)
    }

    func testMaterializationRejectsReplacedPinWithSameIdentity() throws {
        let browser = try makeBrowser()
        defer { browser.tabRuntimeLifecycle.shutdown() }
        let space = Space(name: "Work")
        let window = BrowserWindowState()
        let (stale, replacement) = makePinPair(spaceID: space.id)
        browser.spaceStateOwner.replaceSpaces([space])
        install(replacement, in: browser, spaceID: space.id)
        browser.tabResidenceAuthority.establishResidenceSession(on: window)
        XCTAssertEqual(browser.windowRegistry.register(window), .registered)

        XCTAssertNil(
            makeExecutionCommands(browser: browser).materialize(
                stale,
                in: window,
                currentSpaceID: space.id
            )
        )
        XCTAssertNil(
            browser.liveShortcutTabs.tab(for: replacement.id, in: window.id)
        )
    }

    func testMoveRejectsReplacedPinWithSameIdentity() throws {
        let browser = try makeBrowser()
        defer { browser.tabRuntimeLifecycle.shutdown() }
        let source = Space(name: "Source")
        let destination = Space(name: "Destination")
        let (stale, replacement) = makePinPair(spaceID: source.id)
        browser.spaceStateOwner.replaceSpaces([source, destination])
        install(replacement, in: browser, spaceID: source.id)

        XCTAssertFalse(
            browser.sidebarPinCommands.move(stale, toSpace: destination.id)
        )
        XCTAssertTrue(
            browser.shortcutPinCollectionStateOwner
                .shortcutPin(by: replacement.id) === replacement
        )
        XCTAssertEqual(replacement.spaceId, source.id)
    }

    private func makeBrowser() throws -> BrowserManager {
        let browser = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupModelContainer()
            )
        )
        browser.startupRestoreLifecycle.markLoadFinished()
        browser.startupSessionRestoreOwner.markRestoreOfferConsumed()
        return browser
    }

    private func makeExecutionCommands(
        browser: BrowserManager
    ) -> SidebarPinExecutionCommands {
        SidebarPinExecutionCommands(
            runtime: browser.runtimePortConnection,
            windows: SidebarWindowIdentityQuery(
                registry: browser.windowRegistry
            ),
            pins: browser.shortcutPinCollectionStateOwner,
            materializer: browser.shortcutTabMaterializer,
            profiles: browser.shortcutExecutionProfileAssignments
        )
    }

    private func makePinPair(
        spaceID: UUID
    ) -> (stale: ShortcutPin, replacement: ShortcutPin) {
        let identity = UUID()
        return (
            makePin(id: identity, title: "Stale", spaceID: spaceID),
            makePin(id: identity, title: "Replacement", spaceID: spaceID)
        )
    }

    private func makePin(
        id: UUID,
        title: String,
        spaceID: UUID
    ) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: .spacePinned,
            spaceId: spaceID,
            index: 0,
            launchURL: URL(string: "https://\(title.lowercased()).example")!,
            title: title
        )
    }

    private func install(
        _ pin: ShortcutPin,
        in browser: BrowserManager,
        spaceID: UUID
    ) {
        browser.shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts([
            spaceID: [pin],
        ])
    }
}
