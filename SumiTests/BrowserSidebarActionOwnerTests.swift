import XCTest

@testable import Sumi

@MainActor
final class BrowserSidebarActionOwnerTests: XCTestCase {
    func testSpaceForSidebarActionsPrefersWindowSpaceBeforeCurrentSpace() {
        let harness = makeHarness()
        harness.tabManager.currentSpace = harness.secondarySpace

        XCTAssertEqual(
            harness.owner.spaceForSidebarActions(in: harness.windowState)?.id,
            harness.primarySpace.id
        )
    }

    func testCreateFolderInCurrentSpaceUsesResolvedWindowSpace() {
        let harness = makeHarness()
        harness.tabManager.currentSpace = harness.secondarySpace

        harness.owner.createFolderInCurrentSpace(in: harness.windowState)

        XCTAssertEqual(harness.tabManager.folders(for: harness.primarySpace.id).count, 1)
        XCTAssertTrue(harness.tabManager.folders(for: harness.secondarySpace.id).isEmpty)
    }

    func testSpaceForSidebarActionsWithStaleWindowSpaceDoesNotUseProfileOrGlobalCurrentSpace() {
        let harness = makeHarness()
        harness.windowState.currentSpaceId = UUID()
        harness.windowState.currentProfileId = harness.primaryProfile.id
        harness.tabManager.currentSpace = harness.secondarySpace

        XCTAssertNil(harness.owner.spaceForSidebarActions(in: harness.windowState))
    }

    func testCreateFolderWithMissingWindowSpaceAndProfileDoesNotUseGlobalCurrentSpace() {
        let harness = makeHarness()
        harness.windowState.currentSpaceId = UUID()
        harness.windowState.currentProfileId = nil
        harness.tabManager.currentSpace = harness.secondarySpace

        XCTAssertNil(harness.owner.spaceForSidebarActions(in: harness.windowState))

        harness.owner.createFolderInCurrentSpace(in: harness.windowState)

        XCTAssertTrue(harness.tabManager.folders(for: harness.primarySpace.id).isEmpty)
        XCTAssertTrue(harness.tabManager.folders(for: harness.secondarySpace.id).isEmpty)
    }

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager()
        let tabManager = browserManager.tabManager
        let primaryProfile = Profile(name: "Primary")
        let secondaryProfile = Profile(name: "Secondary")
        let primarySpace = Space(name: "Primary", profileId: primaryProfile.id)
        let secondarySpace = Space(name: "Secondary", profileId: secondaryProfile.id)
        let windowState = BrowserWindowState()
        let liveFolderManager = SumiLiveFolderManager()

        tabManager.spaces = [primarySpace, secondarySpace]
        tabManager.currentSpace = primarySpace
        windowState.currentSpaceId = primarySpace.id
        windowState.currentProfileId = primaryProfile.id
        windowState.tabManager = tabManager

        let owner = BrowserSidebarActionOwner(
            dependencies: BrowserSidebarActionOwner.Dependencies(
                tabManager: { tabManager },
                liveFolderManager: { liveFolderManager }
            )
        )

        return Harness(
            owner: owner,
            tabManager: tabManager,
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
    let tabManager: TabManager
    let windowState: BrowserWindowState
    let primaryProfile: Profile
    let primarySpace: Space
    let secondarySpace: Space
}
