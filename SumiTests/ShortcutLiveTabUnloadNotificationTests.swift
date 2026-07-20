import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class ShortcutLiveTabUnloadNotificationTests: XCTestCase {
    func testTabUnloadedNotificationFactoryUsesExpectedCopy() {
        let single = BrowserNotification.tabUnloaded(count: 1)
        XCTAssertEqual(single.messageKey, "tab-unloaded")
        XCTAssertEqual(single.title, "1 tab unloaded")
        XCTAssertEqual(single.subtitle, "Click the tab to reload it")
        XCTAssertEqual(single.duration, 2.0)
        XCTAssertEqual(single.icon, "moon.zzz")
        XCTAssertNil(single.action)

        let multiple = BrowserNotification.tabUnloaded(count: 3)
        XCTAssertEqual(multiple.title, "3 tabs unloaded")

        let splitView = BrowserNotification.splitViewUnloaded(tabCount: 3)
        XCTAssertEqual(splitView.messageKey, "split-view-unloaded")
        XCTAssertEqual(splitView.title, "3-tab Split View unloaded")
        XCTAssertEqual(
            splitView.subtitle,
            "Click the Split View to reload it"
        )
        XCTAssertEqual(splitView.icon, "rectangle.split.2x1")

        let closedSplitView = BrowserNotification.splitViewClosure(
            tabCount: 4,
            undoShortcut: "⇧⌘T",
            action: nil
        )
        XCTAssertEqual(closedSplitView.messageKey, "split-view-closed")
        XCTAssertEqual(closedSplitView.title, "4-tab Split View closed")
        XCTAssertEqual(closedSplitView.subtitle, "Press ⇧⌘T to reopen")
    }

    func testRuntimeContextForwardsTabUnloadedNotification() {
        let windowState = BrowserWindowState()
        let spy = NotificationPresentingSpy()

        let context = TestRuntimePorts.make(
            notifications: { spy }
        )

        context.notifications()?.presentTabUnloadedNotification(count: 2, in: windowState)

        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.count), [2])
        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.windowState?.id), [windowState.id])
    }

    func testShortcutLiveTabClosePublicationPresentsTabUnloadedNotification() throws {
        let tabManager = BrowserManager()
        let space = try XCTUnwrap(tabManager.sidebarSpaceLifecycle.createSpace(
            name: "Workspace",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: nil
        ))
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://pinned.example")),
            title: "Pinned"
        )
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        XCTAssertEqual(
            tabManager.windowRegistry.register(windowState),
            .registered
        )

        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role

        let spy = NotificationPresentingSpy()
        let publication = ShortcutLiveTabClosePublication(
            pins: tabManager.shortcutPinCollectionStateOwner,
            recentlyClosed: RecentlyClosedManager(),
            notifications: spy
        )

        publication.captureHistory(for: liveTab, in: windowState)
        publication.notifyClose(in: windowState)

        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.count), [1])
        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.windowState?.id), [windowState.id])
        XCTAssertIdentical(
            tabManager.shortcutPresentationOwner.shortcutLiveTab(
                for: pin.id,
                in: windowState.id
            ),
            liveTab
        )
    }

    func testClosingHostedSplitUnloadsEveryMemberAndUsesSplitNotification()
        throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            hostedSplit: true
        )

        XCTAssertTrue(fixture.browser.shortcutLiveTabClose.close(
            fixture.liveTabs[0],
            in: fixture.window
        ))

        XCTAssertTrue(fixture.liveTabs.allSatisfy { tab in
            fixture.browser.liveShortcutTabs.entry(tabId: tab.id) == nil
                && fixture.browser.tabCollectionMembershipOwner
                    .tab(for: tab.id) == nil
        })
        let notification = try XCTUnwrap(
            fixture.window.inAppNotifications.items.first?.notification
        )
        XCTAssertEqual(notification.messageKey, "split-view-unloaded")
        XCTAssertEqual(notification.title, "2-tab Split View unloaded")
        XCTAssertEqual(
            notification.subtitle,
            "Click the Split View to reload it"
        )
    }

    func testSidebarUnloadSplitCommandUsesSplitNotification() throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            hostedSplit: true
        )
        let context = fixture.browser.composeSidebarBrowserContext(
            spaceLifecycle: fixture.browser.sidebarSpaceLifecycle
        )

        context.splitGroupLifecycle.unload(
            fixture.group,
            in: fixture.window
        )

        XCTAssertTrue(fixture.liveTabs.allSatisfy {
            fixture.browser.liveShortcutTabs.entry(tabId: $0.id) == nil
        })
        let notification = try XCTUnwrap(
            fixture.window.inAppNotifications.items.first?.notification
        )
        XCTAssertEqual(notification.messageKey, "split-view-unloaded")
        XCTAssertEqual(notification.title, "2-tab Split View unloaded")
    }
}
