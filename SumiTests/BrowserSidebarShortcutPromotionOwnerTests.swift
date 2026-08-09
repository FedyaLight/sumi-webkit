@testable import Sumi
import XCTest

@MainActor
final class SidebarShortcutPromotionOwnerTests: XCTestCase {
    func testPinShortcutGloballyCopiesShortcutWithLiveShortcutTitle() throws {
        let harness = makePromotionHarness()
        let pin = try makeShortcutPin(
            title: "Saved Title",
            spaceId: harness.space.id
        )
        let liveTab = makeTab(name: "  Live Title  ")
        harness.browserManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: harness.space.id)

        pinShortcutGlobally(
            pin,
            harness: harness,
            liveTab: liveTab
        )

        XCTAssertEqual(
            harness.browserManager.shortcutPinCollectionStateOwner
                .favoritePins(for: harness.profile.id)
                .first?.title,
            "Live Title"
        )
    }

    func testPinShortcutGloballyFallsBackToPinTitle() throws {
        let harness = makePromotionHarness()
        let pin = try makeShortcutPin(
            title: "Saved Title",
            spaceId: harness.space.id
        )
        harness.browserManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: harness.space.id)

        pinShortcutGlobally(
            pin,
            harness: harness,
            liveTab: nil
        )

        XCTAssertEqual(
            harness.browserManager.shortcutPinCollectionStateOwner
                .favoritePins(for: harness.profile.id)
                .first?.title,
            "Saved Title"
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
        harness.browserManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([sourcePin], for: harness.space.id)

        pinShortcutGlobally(
            sourcePin,
            harness: harness,
            liveTab: nil
        )

        XCTAssertEqual(harness.browserManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: harness.space.id).map(\.id), [sourcePin.id])
        let favorite = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner.favoritePins(for: harness.profile.id).first
        )
        XCTAssertNotEqual(favorite.id, sourcePin.id)
        XCTAssertEqual(favorite.role, .favorite)
        XCTAssertEqual(favorite.profileId, harness.profile.id)
        XCTAssertNil(favorite.spaceId)
        XCTAssertNil(favorite.folderId)
        XCTAssertEqual(favorite.executionProfileId, executionProfileId)
        XCTAssertEqual(favorite.iconAsset, "star")
        XCTAssertEqual(favorite.launchURL, sourcePin.launchURL)
        XCTAssertEqual(favorite.title, "Saved Title")
    }

    func testPinShortcutGloballySkipsDuplicateFavoriteURL() throws {
        let harness = makePromotionHarness()
        let sourcePin = try makeShortcutPin(title: "Saved Title", spaceId: harness.space.id)
        let existingFavorite = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: harness.profile.id,
            index: 0,
            launchURL: sourcePin.launchURL,
            title: "Existing"
        )
        harness.browserManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([sourcePin], for: harness.space.id)
        harness.browserManager.structuralCollectionMutationOwner.setPinnedTabs([existingFavorite], for: harness.profile.id)

        pinShortcutGlobally(
            sourcePin,
            harness: harness,
            liveTab: nil
        )

        XCTAssertEqual(
            harness.browserManager.shortcutPinCollectionStateOwner.favoritePins(for: harness.profile.id).map(\.id),
            [existingFavorite.id]
        )
        XCTAssertEqual(harness.browserManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: harness.space.id).map(\.id), [sourcePin.id])
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

    private func pinShortcutGlobally(
        _ pin: ShortcutPin,
        harness: PromotionHarness,
        liveTab: Tab?
    ) {
        _ = harness.browserManager.sidebarPinCommands
            .copyToFavorite(
                pin,
                title: pin.resolvedDisplayTitle(liveTab: liveTab),
                context: FavoriteShortcutPlacementOwner.TargetContext(
                    windowState: harness.windowState,
                    spaceId: harness.space.id
                )
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
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
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

@MainActor
private struct PromotionHarness {
    let browserManager: BrowserManager
    let profile: Profile
    let space: Space
    let windowState: BrowserWindowState
}
