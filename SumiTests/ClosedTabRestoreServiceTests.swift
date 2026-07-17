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
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.currentProfileSpace).first
        )
        XCTAssertEqual(restored.url, tabState.url)
        XCTAssertEqual(restored.name, "Closed")
        XCTAssertTrue(try XCTUnwrap(restored.restoredCanGoBack))
        XCTAssertFalse(try XCTUnwrap(restored.restoredCanGoForward))
        XCTAssertTrue(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.fallbackSpace).isEmpty
        )
        XCTAssertEqual(
            harness.browserManager.tabStateStore.selection.currentTab?.id,
            restored.id
        )
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

        XCTAssertTrue(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.currentProfileSpace).isEmpty
        )
        XCTAssertTrue(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.fallbackSpace).isEmpty
        )
        XCTAssertNil(harness.browserManager.tabStateStore.selection.currentTab)
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
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.currentProfileSpace).first
        )
        XCTAssertEqual(restored.url, currentURL)
        XCTAssertTrue(try XCTUnwrap(restored.restoredCanGoBack))
        XCTAssertTrue(try XCTUnwrap(restored.restoredCanGoForward))
        XCTAssertEqual(windowState.currentTabId, restored.id)
    }

    private func makeHarness(activeWindow: BrowserWindowState? = nil) -> Harness {
        let browserManager = BrowserManager()
        let fallbackProfile = Profile(name: "Fallback")
        let currentProfile = Profile(name: "Current")
        let fallbackSpace = Space(name: "Fallback", profileId: fallbackProfile.id)
        let currentProfileSpace = Space(name: "Current", profileId: currentProfile.id)

        browserManager.profileManager.profiles = [fallbackProfile, currentProfile]
        browserManager.currentProfile = currentProfile
        browserManager.spaceStateOwner.replaceSpaces([fallbackSpace, currentProfileSpace])
        browserManager.structuralCollectionMutationOwner.setTabs([], for: fallbackSpace.id)
        browserManager.structuralCollectionMutationOwner.setTabs([], for: currentProfileSpace.id)
        browserManager.spaceStateOwner.replaceCurrentSpace(fallbackSpace)

        let service = ClosedTabRestoreService(
            regularLifecycle: browserManager.regularTabLifecycleOwner,
            destinations: ClosedTabDestinationResolver(
                spaces: browserManager.spaceStateOwner,
                windows: browserManager.windowRegistry
            ),
            publication: ClosedTabRestorePublication(
                activeSelection: browserManager.activeSelectionOwner,
                browserSelection: browserManager.browserTabSelection
            )
        )
        if let activeWindow {
            browserManager.windowRegistry.register(activeWindow)
            browserManager.windowRegistry.setActive(activeWindow)
        }
        return Harness(
            browserManager: browserManager,
            fallbackSpace: fallbackSpace,
            currentProfileSpace: currentProfileSpace,
            service: service
        )
    }

    @MainActor
    private struct Harness {
        let browserManager: BrowserManager
        let fallbackSpace: Space
        let currentProfileSpace: Space
        let service: ClosedTabRestoreService
    }
}
