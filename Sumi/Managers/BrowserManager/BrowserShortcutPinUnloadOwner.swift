import Foundation

@MainActor
final class BrowserShortcutPinUnloadOwner {
    private let shortcuts: TabShortcutPresentationOwner
    private let close: ShortcutLiveTabCloseService
    private let notifications: BrowserNotificationPresenter

    init(
        shortcuts: TabShortcutPresentationOwner,
        close: ShortcutLiveTabCloseService,
        notifications: BrowserNotificationPresenter
    ) {
        self.shortcuts = shortcuts
        self.close = close
        self.notifications = notifications
    }

    func unloadShortcutPin(_ pin: ShortcutPin, in windowState: BrowserWindowState) {
        _ = unloadShortcutPin(pin, in: windowState, suppressNotification: false)
    }

    /// Routes every live instance through browser close orchestration so split
    /// proxy repair, recently-closed capture, persistence, and notification
    /// policy remain above the Tab runtime retirement boundary.
    @discardableResult
    func unloadShortcutPin(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        suppressNotification: Bool
    ) -> Bool {
        guard let liveTab = shortcuts.shortcutLiveTab(
            for: pin.id,
            in: windowState.id
        ) else {
            return false
        }
        return close.close(
            liveTab,
            in: windowState,
            presentNotification: !suppressNotification
        )
    }

    func unloadShortcutPins(_ pins: [ShortcutPin], in windowState: BrowserWindowState) {
        var unloadedCount = 0
        for pin in pins {
            if unloadShortcutPin(pin, in: windowState, suppressNotification: true) {
                unloadedCount += 1
            }
        }

        if unloadedCount > 0 {
            notifications.presentTabUnloadedNotification(
                count: unloadedCount,
                in: windowState
            )
        }
    }
}
