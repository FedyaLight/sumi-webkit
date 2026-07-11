import XCTest

@testable import Sumi

@MainActor
final class ClosedTabRestoreServiceTests: XCTestCase {
    func testRestoreUsesSourceProfileSpaceInsteadOfGlobalFallback() throws {
        let harness = makeHarness()
        let tabState = RecentlyClosedTabState(
            id: UUID(),
            title: "Closed",
            url: try XCTUnwrap(URL(string: "https://closed.example")),
            sourceSpaceId: nil,
            currentURL: nil,
            canGoBack: true,
            canGoForward: false,
            profileId: try XCTUnwrap(harness.currentProfileSpace.profileId)
        )

        XCTAssertTrue(harness.service.restore(tabState))

        let restored = try XCTUnwrap(
            harness.tabManager.regularTabCollectionOwner.tabs(in: harness.currentProfileSpace).first
        )
        XCTAssertEqual(restored.url, tabState.url)
        XCTAssertEqual(restored.name, "Closed")
        XCTAssertTrue(try XCTUnwrap(restored.restoredCanGoBack))
        XCTAssertFalse(try XCTUnwrap(restored.restoredCanGoForward))
        XCTAssertTrue(harness.tabManager.regularTabCollectionOwner.tabs(in: harness.fallbackSpace).isEmpty)
        XCTAssertEqual(harness.tabManager.selectionStateOwner.currentTab?.id, restored.id)
    }

    func testRestoreFailsWithoutResolvableSpaceAndCreatesNothing() {
        let harness = makeHarness()
        let tabState = RecentlyClosedTabState(
            id: UUID(),
            title: "Closed",
            url: URL(string: "https://closed.example")!,
            sourceSpaceId: nil,
            currentURL: nil,
            canGoBack: false,
            canGoForward: false,
            profileId: nil
        )

        XCTAssertFalse(harness.service.restore(tabState))

        XCTAssertTrue(harness.tabManager.regularTabCollectionOwner.tabs(in: harness.currentProfileSpace).isEmpty)
        XCTAssertTrue(harness.tabManager.regularTabCollectionOwner.tabs(in: harness.fallbackSpace).isEmpty)
        XCTAssertNil(harness.tabManager.selectionStateOwner.currentTab)
        XCTAssertTrue(harness.selectedTabs.isEmpty)
    }

    func testRestorePrefersCurrentURLAndSelectsInProvidedWindow() throws {
        let windowState = BrowserWindowState()
        let harness = makeHarness(activeWindow: windowState)
        windowState.currentSpaceId = harness.currentProfileSpace.id
        let launchURL = try XCTUnwrap(URL(string: "https://closed.example/start"))
        let currentURL = try XCTUnwrap(URL(string: "https://closed.example/drifted"))
        let tabState = RecentlyClosedTabState(
            id: UUID(),
            title: "Drifted",
            url: launchURL,
            sourceSpaceId: harness.currentProfileSpace.id,
            currentURL: currentURL,
            canGoBack: true,
            canGoForward: true,
            profileId: try XCTUnwrap(harness.currentProfileSpace.profileId)
        )

        XCTAssertTrue(harness.service.restore(tabState))

        let restored = try XCTUnwrap(
            harness.tabManager.regularTabCollectionOwner.tabs(in: harness.currentProfileSpace).first
        )
        XCTAssertEqual(restored.url, currentURL)
        XCTAssertTrue(try XCTUnwrap(restored.restoredCanGoBack))
        XCTAssertTrue(try XCTUnwrap(restored.restoredCanGoForward))
        XCTAssertEqual(harness.selectedTabs.map(\.tab.id), [restored.id])
        XCTAssertIdentical(harness.selectedTabs.first?.window, windowState)
    }

    private func makeHarness(activeWindow: BrowserWindowState? = nil) -> Harness {
        let browserManager = BrowserManager()
        let fallbackProfile = Profile(name: "Fallback")
        let currentProfile = Profile(name: "Current")
        let fallbackSpace = Space(name: "Fallback", profileId: fallbackProfile.id)
        let currentProfileSpace = Space(name: "Current", profileId: currentProfile.id)

        browserManager.profileManager.profiles = [fallbackProfile, currentProfile]
        browserManager.currentProfile = currentProfile
        browserManager.tabManager.spaceStateOwner.replaceSpaces([fallbackSpace, currentProfileSpace])
        browserManager.tabManager.structuralCollectionMutationOwner.setTabs([], for: fallbackSpace.id)
        browserManager.tabManager.structuralCollectionMutationOwner.setTabs([], for: currentProfileSpace.id)
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(fallbackSpace)

        let selectionRecorder = TabSelectionRecorder()
        let service = ClosedTabRestoreService(
            tabManager: { browserManager.tabManager },
            activeWindow: { activeWindow },
            selectRestoredTab: { tab, windowState in
                selectionRecorder.selected.append((tab, windowState))
            }
        )
        return Harness(
            browserManager: browserManager,
            tabManager: browserManager.tabManager,
            fallbackSpace: fallbackSpace,
            currentProfileSpace: currentProfileSpace,
            service: service,
            selectionRecorder: selectionRecorder
        )
    }

    @MainActor
    private struct Harness {
        let browserManager: BrowserManager
        let tabManager: TabManager
        let fallbackSpace: Space
        let currentProfileSpace: Space
        let service: ClosedTabRestoreService
        let selectionRecorder: TabSelectionRecorder

        var selectedTabs: [(tab: Tab, window: BrowserWindowState)] {
            selectionRecorder.selected
        }
    }
}
