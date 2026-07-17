import SumiDomain
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class BrowserShortcutCommandRoutingTests: XCTestCase {
    func testTabCyclingSelectsRelativeIndexAndWraps() throws {
        let harness = try makeHarness()
        let first = createTab("https://first.example", in: harness)
        let second = createTab("https://second.example", in: harness)
        let third = createTab("https://third.example", in: harness)
        harness.windowState.currentTabId = second.id

        let router = harness.browserManager.shortcutActionRouter
        router.execute(.nextTab)
        XCTAssertEqual(harness.windowState.currentTabId, third.id)
        router.execute(.nextTab)
        XCTAssertEqual(harness.windowState.currentTabId, first.id)
        router.execute(.previousTab)
        XCTAssertEqual(harness.windowState.currentTabId, third.id)
    }

    func testSelectByIndexAndLastUseVisibleTabsForActiveWindow() throws {
        let harness = try makeHarness()
        let first = createTab("https://first.example", in: harness)
        let second = createTab("https://second.example", in: harness)
        harness.windowState.currentTabId = first.id
        let router = harness.browserManager.shortcutActionRouter

        router.execute(.goToTab2)
        XCTAssertEqual(harness.windowState.currentTabId, second.id)
        router.execute(.goToTab5)
        XCTAssertEqual(harness.windowState.currentTabId, second.id)
        router.execute(.goToLastTab)
        XCTAssertEqual(harness.windowState.currentTabId, second.id)
    }

    func testSplitLayoutCreatesThenUpdatesActiveSplit() throws {
        let harness = try makeHarness()
        let tab = createTab("https://split.example", in: harness)
        harness.windowState.currentTabId = tab.id
        let router = harness.browserManager.shortcutActionRouter

        router.execute(.splitVertical)
        XCTAssertEqual(
            harness.browserManager.splitWindowContext.query
                .group(in: harness.windowState.id)?.layoutKind,
            .vertical
        )

        router.execute(.splitGrid)
        XCTAssertEqual(
            harness.browserManager.splitWindowContext.query
                .group(in: harness.windowState.id)?.layoutKind,
            .grid
        )
    }

    func testSpaceCyclingWrapsThroughCanonicalSpaceCatalog() throws {
        let harness = try makeHarness()
        let second = Space(name: "Second", profileId: harness.profile.id)
        let third = Space(name: "Third", profileId: harness.profile.id)
        harness.browserManager.spaceStateOwner.replaceSpaces([
            harness.space,
            second,
            third,
        ])
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(third)
        harness.windowState.currentSpaceId = third.id
        let router = harness.browserManager.shortcutActionRouter

        router.execute(.nextSpace)
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.space.id)
        router.execute(.previousSpace)
        XCTAssertEqual(harness.windowState.currentSpaceId, third.id)
    }

    func testExpandAllFoldersUsesActiveWindowSpace() throws {
        let harness = try makeHarness()
        let folder = TabFolder(name: "Folder", spaceId: harness.space.id)
        folder.isOpen = false
        harness.browserManager.folderCollectionStateOwner
            .replaceFoldersBySpace([harness.space.id: [folder]])

        harness.browserManager.shortcutActionRouter.execute(.expandAllFolders)

        XCTAssertTrue(folder.isOpen)
    }

    private func createTab(
        _ url: String,
        in harness: Harness
    ) -> Tab {
        harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: url,
            in: harness.space,
            activate: false
        )
    }

    private func makeHarness() throws -> Harness {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let profile = Profile(name: "Primary")
        let space = Space(name: "Work", profileId: profile.id)
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)
        registry.register(windowState)
        registry.setActive(windowState)

        return Harness(
            browserManager: browserManager,
            registry: registry,
            windowState: windowState,
            profile: profile,
            space: space
        )
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

private struct Harness {
    let browserManager: BrowserManager
    let registry: WindowRegistry
    let windowState: BrowserWindowState
    let profile: Profile
    let space: Space
}
