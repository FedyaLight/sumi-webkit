import Foundation

@MainActor
final class BrowserShortcutPinUnloadOwner {
    struct Dependencies {
        let selectedShortcutLiveTab: @MainActor (UUID, BrowserWindowState) -> Tab?
        let closeTab: @MainActor (Tab, BrowserWindowState) -> Void
        let userInitiatedUnload: @MainActor (UUID, BrowserWindowState, Bool) -> Bool
        let notifications: @MainActor () -> (any BrowserNotificationPresenting)?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
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
        if let current = dependencies.selectedShortcutLiveTab(pin.id, windowState) {
            dependencies.closeTab(current, windowState)
            return false
        }

        return dependencies.userInitiatedUnload(
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
            dependencies.notifications()?.presentTabUnloadedNotification(
                count: unloadedCount,
                in: windowState
            )
        }
    }
}

extension BrowserShortcutPinUnloadOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            selectedShortcutLiveTab: { [weak browserManager] pinId, windowState in
                browserManager?.tabManager.shortcutPresentationOwner.selectedShortcutLiveTab(
                    for: pinId,
                    in: windowState
                )
            },
            closeTab: { [weak browserManager] tab, windowState in
                browserManager?.tabLifecycleService.closeOrchestration.closeTab(tab, in: windowState)
            },
            userInitiatedUnload: { [weak browserManager] pinId, windowState, presentNotification in
                browserManager?.tabManager.shortcutLiveTabOwner.userInitiatedUnload(
                    pinId: pinId,
                    in: windowState,
                    presentNotification: presentNotification
                ) ?? false
            },
            notifications: { [weak browserManager] in
                browserManager?.notificationPresenter
            }
        )
    }
}
