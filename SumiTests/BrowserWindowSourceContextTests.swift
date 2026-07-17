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
        let fixture = Fixture(space: space, tab: tab)

        XCTAssertEqual(
            fixture.resolver.resolve(
                tab: tab,
                window: window
            )?.context,
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
        let fixture = Fixture(space: space, tab: tab)

        XCTAssertEqual(
            fixture.resolver.resolve(
                tab: tab,
                window: window
            )?.context,
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
        let fixture = Fixture(spaces: [tabSpace, windowSpace], tab: tab)

        XCTAssertNil(fixture.resolver.resolve(
            tab: tab,
            window: window
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
        let fixture = Fixture(space: space, tab: tab)

        XCTAssertNil(fixture.resolver.resolve(
            tab: tab,
            window: window
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
        let fixture = Fixture(space: space, tab: tab)

        XCTAssertNil(fixture.resolver.resolve(
            tab: tab,
            window: window
        ))
    }

    @MainActor
    private final class Fixture {
        private let browserManager: BrowserManager
        let resolver: BrowserWindowSourceContextResolver

        convenience init(space: Space, tab: Tab) {
            self.init(spaces: [space], tab: tab)
        }

        init(spaces: [Space], tab: Tab) {
            let browserManager = BrowserManager()
            browserManager.spaceStateOwner.replaceSpaces(spaces)
            if let spaceID = tab.spaceId {
                browserManager.structuralCollectionMutationOwner.setTabs(
                    [tab],
                    for: spaceID
                )
            }
            self.browserManager = browserManager
            resolver = BrowserWindowSourceContextResolver(
                spaces: browserManager.spaceStateOwner,
                regularTabs: browserManager.regularTabCollectionOwner,
                shortcutTabs: browserManager.liveShortcutTabs
            )
        }
    }
}
