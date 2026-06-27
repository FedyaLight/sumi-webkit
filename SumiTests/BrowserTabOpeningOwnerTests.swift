import XCTest

@testable import Sumi

@MainActor
final class BrowserTabOpeningOwnerTests: XCTestCase {
    func testForegroundOpenUsesPreferredSpaceBeforeWindowSpace() {
        let harness = makeHarness()
        harness.windowState.currentSpaceId = harness.primarySpace.id

        let opened = harness.browserManager.openNewTab(
            context: .foreground(
                windowState: harness.windowState,
                preferredSpaceId: harness.secondarySpace.id
            )
        )

        XCTAssertEqual(opened.spaceId, harness.secondarySpace.id)
        XCTAssertEqual(harness.windowState.currentTabId, opened.id)
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.secondarySpace.id)
    }

    func testBackgroundOpenFromSourceInsertsAfterSourceWithoutChangingSelection() {
        let harness = makeHarness()
        let source = harness.browserManager.tabManager.createNewTab(
            in: harness.primarySpace,
            activate: false
        )
        let trailing = harness.browserManager.tabManager.createNewTab(
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = source.id

        let opened = harness.browserManager.openNewTab(
            context: .background(
                windowState: harness.windowState,
                sourceTab: source
            )
        )

        XCTAssertEqual(harness.windowState.currentTabId, source.id)
        XCTAssertEqual(
            harness.browserManager.tabManager.tabs(in: harness.primarySpace).map(\.id),
            [source.id, opened.id, trailing.id]
        )
    }

    func testDuplicateUsesWindowSpaceBeforeSourceSpace() {
        let harness = makeHarness()
        let source = harness.browserManager.tabManager.createNewTab(
            in: harness.secondarySpace,
            activate: false
        )
        source.name = "Source"
        harness.windowState.currentSpaceId = harness.primarySpace.id

        harness.browserManager.duplicateTab(source, in: harness.windowState)

        let duplicated = harness.browserManager.tabManager.tabs(in: harness.primarySpace).first
        XCTAssertEqual(duplicated?.name, "Source")
        XCTAssertEqual(duplicated?.url, source.url)
        XCTAssertEqual(harness.windowState.currentTabId, duplicated?.id)
    }

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let primarySpace = Space(name: "Primary", profileId: profile.id)
        let secondarySpace = Space(name: "Secondary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [primarySpace, secondarySpace]
        browserManager.tabManager.currentSpace = primarySpace

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = primarySpace.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return Harness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            windowState: windowState,
            primarySpace: primarySpace,
            secondarySpace: secondarySpace
        )
    }
}

@MainActor
private struct Harness {
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let windowState: BrowserWindowState
    let primarySpace: Space
    let secondarySpace: Space
}
