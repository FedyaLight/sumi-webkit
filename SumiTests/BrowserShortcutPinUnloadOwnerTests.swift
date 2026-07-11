import XCTest

@testable import Sumi

@MainActor
final class BrowserShortcutPinUnloadOwnerTests: XCTestCase {
    func testUnloadShortcutPinRoutesLiveInstanceThroughCloseTab() {
        let windowState = BrowserWindowState()
        let pin = makePin()
        let liveTab = Tab(url: URL(string: "https://selected.example")!, name: "Selected", loadsCachedFaviconOnInit: false)
        var closeTabCalls: [(Tab, BrowserWindowState, Bool)] = []

        let owner = makeOwner(
            shortcutLiveTab: { pinId, _ in pinId == pin.id ? liveTab : nil },
            closeTab: { tab, windowState, presentNotification in
                closeTabCalls.append((tab, windowState, presentNotification))
                return true
            }
        )

        owner.unloadShortcutPin(pin, in: windowState)

        XCTAssertEqual(closeTabCalls.map(\.0.id), [liveTab.id])
        XCTAssertEqual(closeTabCalls.map(\.1.id), [windowState.id])
        XCTAssertEqual(closeTabCalls.map(\.2), [true])
    }

    func testUnloadShortcutPinReturnsFalseWhenNoLiveInstanceExists() {
        let windowState = BrowserWindowState()
        let pin = makePin()
        var closeTabCount = 0

        let owner = makeOwner(
            shortcutLiveTab: { _, _ in nil },
            closeTab: { _, _, _ in
                closeTabCount += 1
                return true
            }
        )

        let didUnload = owner.unloadShortcutPin(
            pin,
            in: windowState,
            suppressNotification: false
        )

        XCTAssertFalse(didUnload)
        XCTAssertEqual(closeTabCount, 0)
    }

    func testUnloadShortcutPinsSuppressesPerTabNotificationsAndPresentsOneAggregate() {
        let windowState = BrowserWindowState()
        let pins = [makePin(), makePin(), makePin()]
        let liveTabsByPinId = Dictionary(uniqueKeysWithValues: pins.map {
            ($0.id, Tab(url: $0.launchURL, name: $0.title, loadsCachedFaviconOnInit: false))
        })
        let spy = NotificationPresentingSpy()
        var closeCalls: [(UUID, Bool)] = []

        let owner = makeOwner(
            shortcutLiveTab: { pinId, _ in liveTabsByPinId[pinId] },
            closeTab: { tab, _, presentNotification in
                closeCalls.append((tab.id, presentNotification))
                return true
            },
            notifications: { spy }
        )

        owner.unloadShortcutPins(pins, in: windowState)

        XCTAssertEqual(closeCalls.map(\.0), pins.compactMap { liveTabsByPinId[$0.id]?.id })
        XCTAssertEqual(closeCalls.map(\.1), [false, false, false])
        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.count), [3])
        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.windowState?.id), [windowState.id])
    }

    private func makePin() -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: UUID(),
            index: 0,
            launchURL: URL(string: "https://pinned.example")!,
            title: "Pinned"
        )
    }

    private func makeOwner(
        shortcutLiveTab: @escaping @MainActor (UUID, BrowserWindowState) -> Tab?,
        closeTab: @escaping @MainActor (Tab, BrowserWindowState, Bool) -> Bool,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)? = { nil }
    ) -> BrowserShortcutPinUnloadOwner {
        BrowserShortcutPinUnloadOwner(
            shortcutLiveTab: shortcutLiveTab,
            closeTab: closeTab,
            notifications: notifications
        )
    }
}
