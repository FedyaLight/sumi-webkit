import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowSourceContextTests: XCTestCase {
    func testResolvesOnlyExactRegularTabSpaceProfileChain() throws {
        let profileID = UUID()
        let space = Space(name: "Source", profileId: profileID)
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.profileId = profileID
        tab.spaceId = space.id
        let window = BrowserWindowState()
        window.currentProfileId = profileID
        window.currentSpaceId = space.id
        let tabs = try makeInMemoryTabManager()
        tabs.spaceStateOwner.replaceSpaces([space])
        tabs.regularTabLifecycleOwner.addTab(tab)

        XCTAssertEqual(
            BrowserWindowSourceContextResolver.resolve(
                tab: tab,
                window: window,
                tabs: tabs
            ),
            BrowserWindowSourceContext(
                profileID: profileID,
                spaceID: space.id
            )
        )
    }

    func testResolvesStableTabThatInheritsCanonicalSpaceProfile() throws {
        let profileID = UUID()
        let space = Space(name: "Source", profileId: profileID)
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.spaceId = space.id
        let window = BrowserWindowState()
        window.currentProfileId = profileID
        window.currentSpaceId = space.id
        let tabs = try makeInMemoryTabManager()
        tabs.spaceStateOwner.replaceSpaces([space])
        tabs.regularTabLifecycleOwner.addTab(tab)

        XCTAssertEqual(
            BrowserWindowSourceContextResolver.resolve(
                tab: tab,
                window: window,
                tabs: tabs
            ),
            BrowserWindowSourceContext(
                profileID: profileID,
                spaceID: space.id
            )
        )
    }

    func testRejectsDivergentPhysicalWindowSpace() throws {
        let profileID = UUID()
        let tabSpace = Space(name: "Tab", profileId: profileID)
        let windowSpace = Space(name: "Window", profileId: profileID)
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.profileId = profileID
        tab.spaceId = tabSpace.id
        let window = BrowserWindowState()
        window.currentProfileId = profileID
        window.currentSpaceId = windowSpace.id
        let tabs = try makeInMemoryTabManager()
        tabs.spaceStateOwner.replaceSpaces([tabSpace, windowSpace])
        tabs.regularTabLifecycleOwner.addTab(tab)

        XCTAssertNil(BrowserWindowSourceContextResolver.resolve(
            tab: tab,
            window: window,
            tabs: tabs
        ))
    }

    func testRejectsSpaceWithoutProfilePartition() throws {
        let profileID = UUID()
        let space = Space(name: "Profileless", profileId: nil)
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.profileId = profileID
        tab.spaceId = space.id
        let window = BrowserWindowState()
        window.currentProfileId = profileID
        window.currentSpaceId = space.id
        let tabs = try makeInMemoryTabManager()
        tabs.spaceStateOwner.replaceSpaces([space])
        tabs.regularTabLifecycleOwner.addTab(tab)

        XCTAssertNil(BrowserWindowSourceContextResolver.resolve(
            tab: tab,
            window: window,
            tabs: tabs
        ))
    }

    func testRejectsWindowProfileMismatch() throws {
        let tabProfileID = UUID()
        let space = Space(name: "Source", profileId: tabProfileID)
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.profileId = tabProfileID
        tab.spaceId = space.id
        let window = BrowserWindowState()
        window.currentProfileId = UUID()
        window.currentSpaceId = space.id
        let tabs = try makeInMemoryTabManager()
        tabs.spaceStateOwner.replaceSpaces([space])
        tabs.regularTabLifecycleOwner.addTab(tab)

        XCTAssertNil(BrowserWindowSourceContextResolver.resolve(
            tab: tab,
            window: window,
            tabs: tabs
        ))
    }
}
