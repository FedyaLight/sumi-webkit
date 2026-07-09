import Foundation

@MainActor
final class BrowserShortcutPinUnloadOwner {
    private let selectedShortcutLiveTab: @MainActor (UUID, BrowserWindowState) -> Tab?
    private let closeTab: @MainActor (Tab, BrowserWindowState) -> Void
    private let userInitiatedUnload: @MainActor (UUID, BrowserWindowState, Bool) -> Bool
    private let notifications: @MainActor () -> (any BrowserNotificationPresenting)?

    init(
        selectedShortcutLiveTab: @escaping @MainActor (UUID, BrowserWindowState) -> Tab?,
        closeTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        userInitiatedUnload: @escaping @MainActor (UUID, BrowserWindowState, Bool) -> Bool,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?
    ) {
        self.selectedShortcutLiveTab = selectedShortcutLiveTab
        self.closeTab = closeTab
        self.userInitiatedUnload = userInitiatedUnload
        self.notifications = notifications
    }

    func unloadShortcutPin(_ pin: ShortcutPin, in windowState: BrowserWindowState) {
        _ = unloadShortcutPin(pin, in: windowState, suppressNotification: false)
    }

    /// Unloads one shortcut pin. Selected live tabs route through `closeTab` (which presents
    /// its own unload notification). Non-selected pins call `userInitiatedUnload`.
    ///
    /// - Returns: `true` when a non-selected pin was actually unloaded (for bulk aggregation).
    @discardableResult
    func unloadShortcutPin(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        suppressNotification: Bool
    ) -> Bool {
        if let current = selectedShortcutLiveTab(pin.id, windowState) {
            closeTab(current, windowState)
            return false
        }

        return userInitiatedUnload(
            pin.id,
            windowState,
            !suppressNotification
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
            notifications()?.presentTabUnloadedNotification(
                count: unloadedCount,
                in: windowState
            )
        }
    }
}
