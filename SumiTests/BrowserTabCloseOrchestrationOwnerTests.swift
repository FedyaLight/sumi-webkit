import SumiDomain
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

    func testClosingRegularSplitClosesEveryMemberAndUsesSplitNotification()
        throws {
        let fixture = try makeRegularSplitFixture()

        fixture.browser.tabCloseOrchestration.closeCurrentTab(
            in: fixture.window
        )

        try assertClosedSplit(fixture)
    }

    func testClosingCurrentRegularSplitHandsOffToPreviousTab() throws {
        let fixture = try makeRegularSplitFixture()
        let space = try XCTUnwrap(
            fixture.browser.spaceStateOwner.space(
                with: try XCTUnwrap(fixture.window.currentSpaceId)
            )
        )
        let successor = fixture.browser.regularTabLifecycleOwner.createNewTab(
            url: "https://successor.example",
            in: space,
            activate: false
        )
        fixture.window.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .regularTab(fixture.first.id),
            .regularTab(successor.id),
        ]

        fixture.browser.tabCloseOrchestration.closeCurrentTab(
            in: fixture.window
        )

        XCTAssertEqual(fixture.window.currentTabId, successor.id)
        XCTAssertIdentical(
            fixture.browser.regularTabCollectionOwner.tab(for: successor.id),
            successor
        )
        try assertClosedSplit(fixture)
    }

    func testClosingOneRegularSplitMemberLeavesTheOtherTabOpen() throws {
        let fixture = try makeRegularSplitFixture()

        XCTAssertTrue(
            fixture.browser.tabCloseOrchestration.closeTab(
                fixture.first,
                in: fixture.window
            )
        )

        XCTAssertNil(
            fixture.browser.regularTabCollectionOwner.tab(
                for: fixture.first.id
            )
        )
        XCTAssertIdentical(
            fixture.browser.regularTabCollectionOwner.tab(
                for: fixture.second.id
            ),
            fixture.second
        )
        XCTAssertEqual(fixture.window.currentTabId, fixture.second.id)
        XCTAssertIdentical(
            fixture.window.currentTabId.flatMap {
                fixture.browser.tabCollectionMembershipOwner.tab(for: $0)
            },
            fixture.second
        )
        XCTAssertNil(
            fixture.browser.splitGroupStore.group(id: fixture.group.id)
        )
    }

    func testSidebarCloseSplitCommandUsesSplitNotification() throws {
        let fixture = try makeRegularSplitFixture()
        let context = fixture.browser.composeSidebarBrowserContext(
            spaceLifecycle: fixture.browser.sidebarSpaceLifecycle
        )

        context.splitGroupLifecycle.closeRegular(
            fixture.group,
            in: fixture.window
        )

        try assertClosedSplit(fixture)
    }

    private func assertClosedSplit(
        _ fixture: RegularSplitFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertNil(
            fixture.browser.regularTabCollectionOwner.tab(
                for: fixture.first.id
            ),
            file: file,
            line: line
        )
        XCTAssertNil(
            fixture.browser.regularTabCollectionOwner.tab(
                for: fixture.second.id
            ),
            file: file,
            line: line
        )
        let notification = try XCTUnwrap(
            fixture.window.inAppNotifications.items.first?.notification
        )
        XCTAssertEqual(notification.messageKey, "split-view-closed")
        XCTAssertEqual(notification.title, "2-tab Split View closed")
        XCTAssertNotNil(notification.subtitle)
    }

    private func makeRegularSplitFixture() throws -> RegularSplitFixture {
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
        browser.windowRegistry.setActive(window)
        let first = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://first.example",
            in: space,
            activate: false
        )
        let second = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://second.example",
            in: space,
            activate: false
        )
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .regularTab(first.id),
                .regularTab(second.id),
            ],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(
            group,
            persist: false
        ))
        browser.selectTab(first, in: window)
        return RegularSplitFixture(
            browser: browser,
            window: window,
            first: first,
            second: second,
            group: group
        )
    }
}

@MainActor
private struct RegularSplitFixture {
    let browser: BrowserManager
    let window: BrowserWindowState
    let first: Tab
    let second: Tab
    let group: SplitGroup
}
