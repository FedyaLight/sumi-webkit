import Foundation

@MainActor
struct WindowSessionShortcutRestorer {
    let tabManager: TabManager

    @discardableResult
    func materializeSelectionIfNeeded(
        in windowState: BrowserWindowState
    ) -> Bool {
        if let shortcutPinId = windowState.currentShortcutPinId,
           let pin = tabManager.shortcutPinCollectionStateOwner
            .shortcutPin(by: shortcutPinId) {
            materialize(pin, in: windowState)
            return true
        }

        return materializeRememberedSpaceSelection(in: windowState)
    }

    @discardableResult
    func materializeRememberedSpaceSelection(
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let currentSpaceId = windowState.currentSpaceId,
              let shortcutPinId = windowState
                .selectedShortcutPinForSpace[currentSpaceId],
              let pin = tabManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: shortcutPinId) else {
            return false
        }

        materialize(pin, in: windowState)
        return true
    }

    func materialize(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) {
        let liveTab = tabManager.shortcutPresentationOwner.shortcutLiveTab(
            for: pin.id,
            in: windowState.id
        ) ?? tabManager.shortcutLiveTabOwner.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: windowState.currentSpaceId
        )

        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
        windowState.isShowingEmptyState = false

        if let spaceId = pin.spaceId {
            windowState.currentSpaceId = spaceId
            windowState.selectedShortcutPinForSpace[spaceId] = pin.id
        }
    }
}
