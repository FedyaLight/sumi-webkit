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
    }

    func testRuntimeContextForwardsTabUnloadedNotification() {
        let windowState = BrowserWindowState()
        let spy = NotificationPresentingSpy()

        let context = TabManagerRuntimeContext(
            notifications: { spy }
        )

        context.notifications()?.presentTabUnloadedNotification(count: 2, in: windowState)

        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.count), [2])
        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.windowState?.id), [windowState.id])
    }

    func testShortcutLiveTabCloseOwnerPresentsTabUnloadedNotificationOnMainPath() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
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
        windowState.tabManager = tabManager
        windowState.currentSpaceId = space.id
        tabManager.runtimeContextAttachmentOwner.attach(
            TabManagerRuntimeContext(
                windowState: { [windowState] windowId in
                    windowId == windowState.id ? windowState : nil
                },
                windows: { [(windowState.id, windowState)] }
            )
        )

        let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role

        let spy = NotificationPresentingSpy()
        let owner = BrowserShortcutLiveTabCloseOwner(
            tabManager: { tabManager },
            recentlyClosedManager: { RecentlyClosedManager() },
            fallbackPlanner: {
                BrowserTabCloseFallbackPlanner(
                    selectionService: ShellSelectionService { _ in [] }
                )
            },
            selectTab: { _, _ in },
            performImmediateVisualHandoffIfPossible: { _ in },
            persistWindowSession: { _ in },
            showEmptyState: { _ in },
            restoreShortcutSplitMember: { _, _, _, _ in
                XCTFail("restoreShortcutSplitMember should not be used")
            },
            unloadShortcutHostedSplitGroup: { _, _ in
                XCTFail("unloadShortcutHostedSplitGroup should not be used")
            },
            notifications: { spy }
        )

        owner.close(liveTab, in: windowState)

        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.count), [1])
        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.windowState?.id), [windowState.id])
        XCTAssertNil(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id))
    }
}
