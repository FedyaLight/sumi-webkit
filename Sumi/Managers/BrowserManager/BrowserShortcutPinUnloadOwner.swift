import Foundation

@MainActor
final class BrowserShortcutPinUnloadOwner {
    private let shortcutLiveTab: @MainActor (UUID, BrowserWindowState) -> Tab?
    private let closeTab: @MainActor (Tab, BrowserWindowState, Bool) -> Bool
    private let notifications: @MainActor () -> (any BrowserNotificationPresenting)?

    init(
        shortcutLiveTab: @escaping @MainActor (UUID, BrowserWindowState) -> Tab?,
        closeTab: @escaping @MainActor (Tab, BrowserWindowState, Bool) -> Bool,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?
    ) {
        self.shortcutLiveTab = shortcutLiveTab
        self.closeTab = closeTab
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
        guard let liveTab = shortcutLiveTab(pin.id, windowState) else {
            return false
        }
        return closeTab(liveTab, windowState, !suppressNotification)
    }

    func unloadShortcutPins(_ pins: [ShortcutPin], in windowState: BrowserWindowState) {
        var unloadedCount = 0
        for pin in pins {
            if unloadShortcutPin(pin, in: windowState, suppressNotification: true) {
                unloadedCount += 1
            }
        }

        if unloadedCount > 0 {
            notifications()?.presentTabUnloadedNotification(
                count: unloadedCount,
                in: windowState
            )
        }
    }
}
