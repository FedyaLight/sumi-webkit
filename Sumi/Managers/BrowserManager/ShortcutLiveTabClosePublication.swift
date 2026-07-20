import Foundation

/// Publishes the non-structural terminal effects of a committed live shortcut
/// close. Structural retirement remains transaction-owned elsewhere.
@MainActor
final class ShortcutLiveTabClosePublication {
    private let pins: ShortcutPinCollectionStateOwner
    private let recentlyClosed: RecentlyClosedManager
    private let notifications: any BrowserNotificationPresenting

    init(
        pins: ShortcutPinCollectionStateOwner,
        recentlyClosed: RecentlyClosedManager,
        notifications: any BrowserNotificationPresenting
    ) {
        self.pins = pins
        self.recentlyClosed = recentlyClosed
        self.notifications = notifications
    }

    func captureHistory(
        for tab: Tab,
        in windowState: BrowserWindowState
    ) {
        guard let pinID = tab.shortcutPinId,
              let pin = pins.shortcutPin(by: pinID) else { return }
        recentlyClosed.captureClosedShortcutLiveInstance(
            tab: tab,
            pin: pin,
            sourceWindowId: windowState.id
        )
    }

    func notifyClose(in windowState: BrowserWindowState) {
        notifications.presentTabUnloadedNotification(
            count: 1,
            in: windowState
        )
    }

    func notifySplitViewUnload(
        tabCount: Int,
        in windowState: BrowserWindowState
    ) {
        notifications.presentSplitViewUnloadedNotification(
            tabCount: tabCount,
            in: windowState
        )
    }
}
