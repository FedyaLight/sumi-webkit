import XCTest
@testable import Sumi

@MainActor
final class BrowserSidebarShortcutPromotionOwnerTests: XCTestCase {
    func testPinShortcutGloballyCopiesShortcutWithLiveShortcutTitle() throws {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        let pin = try makeShortcutPin(title: "Saved Title")
        let liveTab = makeTab(name: "  Live Title  ")

        owner.pinShortcutGlobally(pin, in: windowState, spaceId: spaceId, liveTab: liveTab)

        XCTAssertEqual(
            spy.events,
            [
                .copyShortcutPinToEssentials(
                    pin.id,
                    "Live Title",
                    windowState.id,
                    spaceId
                ),
            ]
        )
    }

    func testPinShortcutGloballyFallsBackToPinTitle() throws {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        let pin = try makeShortcutPin(title: "Saved Title")

        owner.pinShortcutGlobally(pin, in: windowState, spaceId: spaceId, liveTab: nil)

        XCTAssertEqual(
            spy.events,
            [
                .copyShortcutPinToEssentials(
                    pin.id,
                    "Saved Title",
                    windowState.id,
                    spaceId
                ),
            ]
        )
    }

    func testPinShortcutGloballyCopiesSavedShortcutMetadataWithoutMovingSource() throws {
        let harness = makePromotionHarness()
        let executionProfileId = UUID()
        let sourcePin = try makeShortcutPin(
            title: "Saved Title",
            spaceId: harness.space.id,
            executionProfileId: executionProfileId,
            iconAsset: "star"
        )
        harness.browserManager.tabManager.setSpacePinnedShortcuts([sourcePin], for: harness.space.id)

        harness.browserManager.sidebarShortcutPromotionOwner.pinShortcutGlobally(
            sourcePin,
            in: harness.windowState,
            spaceId: harness.space.id,
            liveTab: nil
        )

        XCTAssertEqual(harness.browserManager.tabManager.spacePinnedPins(for: harness.space.id).map(\.id), [sourcePin.id])
        let essential = try XCTUnwrap(
            harness.browserManager.tabManager.essentialPins(for: harness.profile.id).first
        )
        XCTAssertNotEqual(essential.id, sourcePin.id)
        XCTAssertEqual(essential.role, .essential)
        XCTAssertEqual(essential.profileId, harness.profile.id)
        XCTAssertNil(essential.spaceId)
        XCTAssertNil(essential.folderId)
        XCTAssertEqual(essential.executionProfileId, executionProfileId)
        XCTAssertEqual(essential.iconAsset, "star")
        XCTAssertEqual(essential.launchURL, sourcePin.launchURL)
        XCTAssertEqual(essential.title, "Saved Title")
    }

    func testPinShortcutGloballySkipsDuplicateEssentialURL() throws {
        let harness = makePromotionHarness()
        let sourcePin = try makeShortcutPin(title: "Saved Title", spaceId: harness.space.id)
        let existingEssential = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: harness.profile.id,
            index: 0,
            launchURL: sourcePin.launchURL,
            title: "Existing"
        )
        harness.browserManager.tabManager.setSpacePinnedShortcuts([sourcePin], for: harness.space.id)
        harness.browserManager.tabManager.setPinnedTabs([existingEssential], for: harness.profile.id)

        harness.browserManager.sidebarShortcutPromotionOwner.pinShortcutGlobally(
            sourcePin,
            in: harness.windowState,
            spaceId: harness.space.id,
            liveTab: nil
        )

        XCTAssertEqual(
            harness.browserManager.tabManager.essentialPins(for: harness.profile.id).map(\.id),
            [existingEssential.id]
        )
        XCTAssertEqual(harness.browserManager.tabManager.spacePinnedPins(for: harness.space.id).map(\.id), [sourcePin.id])
    }

    private func makeOwner(spy: Spy) -> BrowserSidebarShortcutPromotionOwner {
        BrowserSidebarShortcutPromotionOwner(
            dependencies: BrowserSidebarShortcutPromotionOwner.Dependencies(
                copyShortcutPinToEssentials: { pin, title, context in
                    spy.events.append(
                        .copyShortcutPinToEssentials(
                            pin.id,
                            title,
                            context.windowState?.id,
                            context.spaceId
                        )
                    )
                }
            )
        )
    }

    private func makeShortcutPin(
        title: String,
        spaceId: UUID = UUID(),
        executionProfileId: UUID? = nil,
        iconAsset: String? = nil
    ) throws -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            executionProfileId: executionProfileId,
            spaceId: spaceId,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://example.com")),
            title: title,
            iconAsset: iconAsset
        )
    }

    private func makeTab(name: String) -> Tab {
        Tab(
            url: URL(string: "https://example.com/live")!,
            name: name,
            favicon: "star",
            index: 0
        )
    }

    private func makePromotionHarness() -> PromotionHarness {
        let browserManager = BrowserManager()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Work", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        return PromotionHarness(
            browserManager: browserManager,
            profile: profile,
            space: space,
            windowState: windowState
        )
    }
}

private final class Spy {
    var events: [BrowserSidebarShortcutPromotionOwnerTests.Event] = []
}

extension BrowserSidebarShortcutPromotionOwnerTests {
    enum Event: Equatable {
        case copyShortcutPinToEssentials(UUID, String, UUID?, UUID?)
    }
}

@MainActor
private struct PromotionHarness {
    let browserManager: BrowserManager
    let profile: Profile
    let space: Space
    let windowState: BrowserWindowState
}
