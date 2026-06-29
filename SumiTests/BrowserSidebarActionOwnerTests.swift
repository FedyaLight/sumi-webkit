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

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager()
        let tabManager = browserManager.tabManager
        let profile = Profile(name: "Primary")
        let primarySpace = Space(name: "Primary", profileId: profile.id)
        let secondarySpace = Space(name: "Secondary", profileId: profile.id)
        let windowState = BrowserWindowState()
        let liveFolderManager = SumiLiveFolderManager()

        tabManager.spaces = [primarySpace, secondarySpace]
        tabManager.currentSpace = primarySpace
        windowState.currentSpaceId = primarySpace.id
        windowState.currentProfileId = profile.id
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
    let primarySpace: Space
    let secondarySpace: Space
}
