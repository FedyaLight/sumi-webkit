import XCTest

@testable import Sumi

@MainActor
final class BrowserSidebarActionOwnerTests: XCTestCase {
    func testSpaceForSidebarActionsPrefersWindowSpaceBeforeCurrentSpace() {
        let harness = makeHarness()
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(
            harness.secondarySpace
        )

        XCTAssertEqual(
            harness.owner.spaceForSidebarActions(in: harness.windowState)?.id,
            harness.primarySpace.id
        )
    }

    func testCreateFolderInCurrentSpaceUsesResolvedWindowSpace() {
        let harness = makeHarness()
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(
            harness.secondarySpace
        )

        harness.owner.createFolderInCurrentSpace(in: harness.windowState)

        XCTAssertEqual(
            harness.browserManager.tabStateStore.folders
                .folders(for: harness.primarySpace.id).count,
            1
        )
        XCTAssertTrue(
            harness.browserManager.tabStateStore.folders
                .folders(for: harness.secondarySpace.id).isEmpty
        )
    }

    func testSpaceForSidebarActionsWithStaleWindowSpaceDoesNotUseProfileOrGlobalCurrentSpace() {
        let harness = makeHarness()
        harness.windowState.currentSpaceId = UUID()
        harness.windowState.currentProfileId = harness.primaryProfile.id
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(
            harness.secondarySpace
        )

        XCTAssertNil(harness.owner.spaceForSidebarActions(in: harness.windowState))
    }

    func testCreateFolderWithMissingWindowSpaceAndProfileDoesNotUseGlobalCurrentSpace() {
        let harness = makeHarness()
        harness.windowState.currentSpaceId = UUID()
        harness.windowState.currentProfileId = nil
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(
            harness.secondarySpace
        )

        XCTAssertNil(harness.owner.spaceForSidebarActions(in: harness.windowState))

        harness.owner.createFolderInCurrentSpace(in: harness.windowState)

        XCTAssertTrue(
            harness.browserManager.tabStateStore.folders
                .folders(for: harness.primarySpace.id).isEmpty
        )
        XCTAssertTrue(
            harness.browserManager.tabStateStore.folders
                .folders(for: harness.secondarySpace.id).isEmpty
        )
    }

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager(windowRegistry: WindowRegistry())
        let primaryProfile = Profile(name: "Primary")
        let secondaryProfile = Profile(name: "Secondary")
        let primarySpace = Space(name: "Primary", profileId: primaryProfile.id)
        let secondarySpace = Space(name: "Secondary", profileId: secondaryProfile.id)
        let windowState = BrowserWindowState()
        let liveFolderManager = SumiLiveFolderManager()

        browserManager.spaceStateOwner.replaceSpaces([
            primarySpace,
            secondarySpace,
        ])
        browserManager.spaceStateOwner.replaceCurrentSpace(primarySpace)
        windowState.currentSpaceId = primarySpace.id
        windowState.currentProfileId = primaryProfile.id

        let owner = BrowserSidebarActionOwner(
            spaces: browserManager.spaceStateOwner,
            folderCommands: browserManager.sidebarFolderCommands,
            liveFolderManager: liveFolderManager,
            settings: browserManager.settingsState
        )

        return Harness(
            owner: owner,
            browserManager: browserManager,
            windowState: windowState,
            primaryProfile: primaryProfile,
            primarySpace: primarySpace,
            secondarySpace: secondarySpace
        )
    }
}

@MainActor
private struct Harness {
    let owner: BrowserSidebarActionOwner
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let primaryProfile: Profile
    let primarySpace: Space
    let secondarySpace: Space
}
