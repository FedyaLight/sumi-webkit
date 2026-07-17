import XCTest

@testable import Sumi

@MainActor
final class BrowserTabCloseOrchestrationOwnerTests: XCTestCase {
    func testStaleSameIDTabCannotCloseCanonicalRegularTab() throws {
        let browser = BrowserManager()
        let profile = Profile(name: "Profile")
        let space = Space(name: "Space", profileId: profile.id)
        let window = BrowserWindowState()
        browser.profileManager.profiles = [profile]
        browser.currentProfile = profile
        browser.spaceStateOwner.replaceSpaces([space])
        browser.spaceStateOwner.replaceCurrentSpace(space)
        browser.tabResidenceAuthority.establishResidenceSession(on: window)
        window.currentSpaceId = space.id
        window.currentProfileId = profile.id
        XCTAssertEqual(browser.windowRegistry.register(window), .registered)

        let canonical = browser.regularTabLifecycleOwner.createNewTab(
            in: space,
            activate: false
        )
        let stale = Tab(
            id: canonical.id,
            url: canonical.url,
            spaceId: space.id,
            loadsCachedFaviconOnInit: false
        )

        browser.tabCloseOrchestration.closeTab(stale, in: window)

        XCTAssertIdentical(
            browser.regularTabCollectionOwner.tab(for: canonical.id),
            canonical
        )
        XCTAssertTrue(
            browser.tabCollectionMembershipOwner.lookupContainsExact(canonical)
        )
    }

    func testCloseCurrentTabInExplicitWindowIgnoresDifferentActiveWindow() throws {
        let explicitWindow = BrowserWindowState()
        let activeWindow = BrowserWindowState()
        let browser = BrowserManager()
        let explicitTabID = UUID()
        let activeTabID = UUID()
        explicitWindow.currentTabId = explicitTabID
        activeWindow.currentTabId = activeTabID
        XCTAssertEqual(browser.windowRegistry.register(activeWindow), .registered)
        browser.windowRegistry.setActive(activeWindow)

        browser.tabCloseOrchestration.closeCurrentTab(in: explicitWindow)

        XCTAssertNil(explicitWindow.currentTabId)
        XCTAssertEqual(activeWindow.currentTabId, activeTabID)
        XCTAssertIdentical(browser.windowRegistry.activeWindow, activeWindow)
    }
}
