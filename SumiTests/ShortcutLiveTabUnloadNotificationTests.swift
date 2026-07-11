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

        let context = TestRuntimePorts.make(
            notifications: { spy }
        )

        context.notifications()?.presentTabUnloadedNotification(count: 2, in: windowState)

        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.count), [2])
        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.windowState?.id), [windowState.id])
    }

    func testShortcutLiveTabCloseServicePresentsTabUnloadedNotificationOnMainPath() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Workspace")
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
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                windowState: { [windowState] windowId in
                    windowId == windowState.id ? windowState : nil
                },
                windows: { [(windowState.id, windowState)] }
            )
        )

        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role

        let spy = NotificationPresentingSpy()
        let service = ShortcutLiveTabCloseService(
            tabManager: { tabManager },
            recentlyClosedManager: { RecentlyClosedManager() },
            fallbackPlanner: {
                BrowserTabCloseFallbackPlanner(
                    selectionService: ShellSelectionService { _ in [] }
                )
            },
            selectTabWithoutPersistence: { _, _ in /* No-op. */ },
            performImmediateVisualHandoffIfPossible: { _ in /* No-op. */ },
            persistWindowSession: { _ in /* No-op. */ },
            showEmptyStateWithoutPersistence: { _ in /* No-op. */ },
            splitShortcuts: { nil },
            notifications: { spy }
        )

        service.close(liveTab, in: windowState)

        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.count), [1])
        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.windowState?.id), [windowState.id])
        XCTAssertNil(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id))
    }
}
