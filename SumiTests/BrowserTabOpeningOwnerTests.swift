import XCTest

@testable import Sumi

@MainActor
final class BrowserTabOpeningOwnerTests: XCTestCase {
    func testSidebarInsertionPrewarmsExactWebViewBeforeDelayedSelection() throws {
        let harness = makeHarness()

        let opened = harness.browserManager.tabOpening
            .createNewTabAfterSidebarInsertion(
                in: harness.windowState,
                url: "https://prewarm.example"
            )

        let webView = try XCTUnwrap(
            opened.webViewSession.untrackedWebView
        )
        XCTAssertNil(webView.url)
        XCTAssertTrue(
            webView.configuration.sumiIsNormalTabWebViewConfiguration
        )
        XCTAssertIdentical(
            webView.configuration.websiteDataStore,
            harness.primaryProfile.dataStore
        )
        XCTAssertNotNil(
            TabWebViewProcessPrewarmingService.stateForTesting(webView)
        )
        XCTAssertNil(harness.windowState.currentTabId)
    }

    func testDelayedSidebarSelectionRejectsSameIDWindowReplacement() async throws {
        let harness = makeHarness()
        let staleWindow = harness.windowState
        let replacement = BrowserWindowState(id: staleWindow.id)
        harness.browserManager.tabResidenceAuthority.establishResidenceSession(on: replacement)
        replacement.currentSpaceId = harness.primarySpace.id
        replacement.currentProfileId = harness.primaryProfile.id

        let opened = harness.browserManager.tabOpening
            .createNewTabAfterSidebarInsertion(in: staleWindow)
        harness.windowRegistry.unregister(staleWindow.id)
        XCTAssertEqual(
            harness.windowRegistry.register(replacement),
            .registered
        )

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(staleWindow.currentTabId)
        XCTAssertNil(replacement.currentTabId)
        XCTAssertIdentical(
            harness.browserManager.regularTabCollectionOwner.tab(
                for: opened.id
            ),
            opened
        )
    }

    func testForegroundOpenUsesPreferredSpaceBeforeWindowSpace() {
        let harness = makeHarness()
        harness.windowState.currentSpaceId = harness.primarySpace.id

        let opened = harness.browserManager.tabOpening.openNewTab(
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
        let source = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            in: harness.primarySpace,
            activate: false
        )
        let trailing = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = source.id

        let opened = harness.browserManager.tabOpening.openNewTab(
            context: .background(
                windowState: harness.windowState,
                sourceTab: source
            )
        )

        XCTAssertEqual(harness.windowState.currentTabId, source.id)
        XCTAssertEqual(
            harness.browserManager.regularTabCollectionOwner.tabs(in: harness.primarySpace).map(\.id),
            [source.id, opened.id, trailing.id]
        )
    }

    func testBackgroundOpenAdoptsDedicatedWebKitChildWindow() {
        let harness = makeHarness()
        let initialTab = harness.browserManager
            .regularTabLifecycleOwner.createNewTab(
                in: harness.primarySpace,
                activate: false
            )
        harness.windowState.currentTabId = initialTab.id
        harness.windowState.webKitChildWindowIdentity =
            WebKitChildWindowIdentity(initialTabID: initialTab.id)

        let opened = harness.browserManager.tabOpening
            .openNewTab(context: .background(
                windowState: harness.windowState,
                sourceTab: initialTab
            ))

        XCTAssertEqual(harness.windowState.currentTabId, initialTab.id)
        XCTAssertNotEqual(opened.id, initialTab.id)
        XCTAssertNil(harness.windowState.webKitChildWindowIdentity)
    }

    func testDuplicateUsesWindowSpaceBeforeSourceSpace() {
        let harness = makeHarness()
        let source = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            in: harness.secondarySpace,
            activate: false
        )
        source.name = "Source"
        harness.windowState.currentSpaceId = harness.primarySpace.id

        harness.browserManager.tabOpening.duplicateTab(source, in: harness.windowState)

        let duplicated = harness.browserManager.regularTabCollectionOwner.tabs(in: harness.primarySpace).first
        XCTAssertEqual(duplicated?.name, "Source")
        XCTAssertEqual(duplicated?.url, source.url)
        XCTAssertEqual(harness.windowState.currentTabId, duplicated?.id)
    }

    func testCreateNewTabWithoutActiveWindowUsesFirstSpaceInsteadOfGlobalCurrentSpace() {
        let harness = makeHarness()
        harness.windowRegistry.activeWindowId = nil
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(harness.secondarySpace)

        let opened = harness.browserManager.tabOpening.createNewTab()

        XCTAssertEqual(opened.spaceId, harness.primarySpace.id)
        XCTAssertEqual(harness.browserManager.tabStateStore.selection.currentTab?.id, opened.id)
    }

    func testContextlessBackgroundOpenUsesFirstSpaceInsteadOfGlobalCurrentSpace() {
        let harness = makeHarness()
        harness.windowRegistry.activeWindowId = nil
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(harness.secondarySpace)

        let opened = harness.browserManager.tabOpening.openNewTab(context: .background())

        XCTAssertEqual(opened.spaceId, harness.primarySpace.id)
    }

    func testDuplicateFallsBackToWindowProfileSpaceInsteadOfGlobalCurrentSpace() {
        let harness = makeHarness()
        harness.windowState.currentSpaceId = nil
        harness.windowState.currentProfileId = harness.primaryProfile.id
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(harness.secondarySpace)

        let source = Tab(name: "Detached Source")

        harness.browserManager.tabOpening.duplicateTab(source, in: harness.windowState)

        let duplicated = harness.browserManager.regularTabCollectionOwner.tabs(in: harness.primarySpace).first
        XCTAssertEqual(duplicated?.name, "Detached Source")
        XCTAssertEqual(duplicated?.spaceId, harness.primarySpace.id)
        XCTAssertTrue(harness.browserManager.regularTabCollectionOwner.tabs(in: harness.secondarySpace).isEmpty)
    }

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager()
        let windowRegistry = browserManager.windowRegistry
        let primaryProfile = Profile(name: "Primary")
        let primarySpace = Space(name: "Primary", profileId: primaryProfile.id)
        let secondarySpace = Space(name: "Secondary", profileId: primaryProfile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [primaryProfile]
        browserManager.currentProfile = primaryProfile
        browserManager.spaceStateOwner.replaceSpaces([primarySpace, secondarySpace])
        browserManager.spaceStateOwner.replaceCurrentSpace(primarySpace)

        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = primarySpace.id
        windowState.currentProfileId = primaryProfile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return Harness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            windowState: windowState,
            primaryProfile: primaryProfile,
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
    let primaryProfile: Profile
    let primarySpace: Space
    let secondarySpace: Space
}
