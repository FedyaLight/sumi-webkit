import XCTest

@testable import Sumi

@MainActor
final class BrowserShortcutPinUnloadOwnerTests: XCTestCase {
    func testUnloadShortcutPinRoutesSelectedPinThroughCloseTab() {
        let windowState = BrowserWindowState()
        let pin = makePin()
        let selectedTab = Tab(url: URL(string: "https://selected.example")!, name: "Selected", loadsCachedFaviconOnInit: false)
        var closeTabCalls: [(Tab, BrowserWindowState)] = []
        var userInitiatedUnloadCalls: [(UUID, BrowserWindowState, Bool)] = []

        let owner = makeOwner(
            selectedShortcutLiveTab: { pinId, _ in pinId == pin.id ? selectedTab : nil },
            closeTab: { tab, windowState in closeTabCalls.append((tab, windowState)) },
            userInitiatedUnload: { pinId, windowState, presentNotification in
                userInitiatedUnloadCalls.append((pinId, windowState, presentNotification))
                return true
            }
        )

        owner.unloadShortcutPin(pin, in: windowState)

        XCTAssertEqual(closeTabCalls.map(\.0.id), [selectedTab.id])
        XCTAssertEqual(closeTabCalls.map(\.1.id), [windowState.id])
        XCTAssertTrue(userInitiatedUnloadCalls.isEmpty)
    }

    func testUnloadShortcutPinUnloadsNonSelectedPinWithNotification() {
        let windowState = BrowserWindowState()
        let pin = makePin()
        var closeTabCalls: [(Tab, BrowserWindowState)] = []
        var userInitiatedUnloadCalls: [(UUID, BrowserWindowState, Bool)] = []

        let owner = makeOwner(
            selectedShortcutLiveTab: { _, _ in nil },
            closeTab: { tab, windowState in closeTabCalls.append((tab, windowState)) },
            userInitiatedUnload: { pinId, windowState, presentNotification in
                userInitiatedUnloadCalls.append((pinId, windowState, presentNotification))
                return true
            }
        )

        owner.unloadShortcutPin(pin, in: windowState)

        XCTAssertTrue(closeTabCalls.isEmpty)
        XCTAssertEqual(userInitiatedUnloadCalls.map(\.0), [pin.id])
        XCTAssertEqual(userInitiatedUnloadCalls.map(\.1.id), [windowState.id])
        XCTAssertEqual(userInitiatedUnloadCalls.map(\.2), [true])
    }

    func testUnloadShortcutPinsAggregatesNonSelectedUnloadsAndPresentsSingleNotification() {
        let windowState = BrowserWindowState()
        let selectedPin = makePin()
        let unloadedPinA = makePin()
        let unloadedPinB = makePin()
        let selectedTab = Tab(url: URL(string: "https://selected.example")!, name: "Selected", loadsCachedFaviconOnInit: false)
        let spy = NotificationPresentingSpy()
        var closeTabCount = 0
        var userInitiatedUnloadCalls: [(UUID, BrowserWindowState, Bool)] = []

        let owner = makeOwner(
            selectedShortcutLiveTab: { pinId, _ in pinId == selectedPin.id ? selectedTab : nil },
            closeTab: { _, _ in closeTabCount += 1 },
            userInitiatedUnload: { pinId, windowState, presentNotification in
                userInitiatedUnloadCalls.append((pinId, windowState, presentNotification))
                return pinId == unloadedPinA.id || pinId == unloadedPinB.id
            },
            notifications: { spy }
        )

        owner.unloadShortcutPins([selectedPin, unloadedPinA, unloadedPinB], in: windowState)

        XCTAssertEqual(closeTabCount, 1)
        XCTAssertEqual(userInitiatedUnloadCalls.map(\.0), [unloadedPinA.id, unloadedPinB.id])
        XCTAssertEqual(userInitiatedUnloadCalls.map(\.2), [false, false])
        XCTAssertEqual(spy.presentTabUnloadedNotificationCalls.map(\.count), [2])
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
        selectedShortcutLiveTab: @escaping @MainActor (UUID, BrowserWindowState) -> Tab?,
        closeTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        userInitiatedUnload: @escaping @MainActor (UUID, BrowserWindowState, Bool) -> Bool,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)? = { nil }
    ) -> BrowserShortcutPinUnloadOwner {
        BrowserShortcutPinUnloadOwner(
            dependencies: BrowserShortcutPinUnloadOwner.Dependencies(
                selectedShortcutLiveTab: selectedShortcutLiveTab,
                closeTab: closeTab,
                userInitiatedUnload: userInitiatedUnload,
                notifications: notifications
            )
        )
    }
}
