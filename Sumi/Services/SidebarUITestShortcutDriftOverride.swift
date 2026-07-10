import Foundation

enum SidebarUITestShortcutDriftOverride {
    static let pinIDEnvironmentKey = "SUMI_SIDEBAR_DRIFT_SHORTCUT_PIN_ID"
    static let urlEnvironmentKey = "SUMI_SIDEBAR_DRIFT_URL"

    @MainActor
    static func applyIfNeeded(
        to windowState: BrowserWindowState,
        tabManager: TabManager
    ) {
        guard let pinIDRaw = ProcessInfo.processInfo.environment[pinIDEnvironmentKey],
              let urlRaw = ProcessInfo.processInfo.environment[urlEnvironmentKey],
              let pinID = UUID(uuidString: pinIDRaw),
              let driftURL = URL(string: urlRaw),
              let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinID)
        else {
            return
        }

        let liveTab = tabManager.shortcutPresentationOwner.shortcutLiveTab(
            for: pin.id,
            in: windowState.id
        ) ?? tabManager.shortcutLiveTabOwner.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: pin.spaceId ?? windowState.currentSpaceId
        )
        liveTab.url = driftURL

        if let spaceId = pin.spaceId {
            windowState.currentSpaceId = spaceId
            windowState.selectedShortcutPinForSpace[spaceId] = pin.id
        }
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
    }
}
