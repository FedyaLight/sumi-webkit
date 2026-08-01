import Foundation

@MainActor
struct WindowSessionShortcutRestorer {
    let pins: ShortcutPinCollectionStateOwner
    let activation: ShortcutPresentationActivationService

    func materializeRestoredLiveSessions(
        in windowState: BrowserWindowState
    ) {
        for session in windowState.restorationState
            .consumeShortcutLiveSessions() {
            guard let pin = pins.shortcutPin(by: session.shortcutPinId),
                  pin.role == .essential
                    || pin.spaceId == session.presentationSpaceId
            else { continue }
            _ = activation.commitActivation(
                pin,
                in: windowState.id,
                presentationSpaceID: session.presentationSpaceId
            ) { liveTab in
                let previousURL = liveTab.url
                if previousURL != session.currentURL {
                    if liveTab.resolvedCurrentWebView() != nil {
                        liveTab.loadURL(session.currentURL)
                    } else {
                        _ = liveTab.beginMainFrameNavigationIntent(
                            to: session.currentURL
                        )
                        liveTab.url = session.currentURL
                    }
                }
                let restoredTitle = session.title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if restoredTitle.isEmpty == false {
                    liveTab.name = restoredTitle
                }
                _ = liveTab.applyCachedFaviconOrPlaceholder(
                    for: session.currentURL
                )
            }
        }
    }

    @discardableResult
    func materializeSelectionIfNeeded(
        in windowState: BrowserWindowState
    ) -> Bool {
        if let shortcutPinId = windowState.currentShortcutPinId,
           let pin = pins.shortcutPin(by: shortcutPinId),
           pin.role == .essential || pin.spaceId == windowState.currentSpaceId {
            return materialize(pin, in: windowState)
        }

        if windowState.currentShortcutPinId != nil
            || windowState.currentShortcutPinRole != nil {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
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
              let pin = pins.shortcutPin(by: shortcutPinId),
              pin.role == .spacePinned,
              pin.spaceId == currentSpaceId else {
            if let currentSpaceId = windowState.currentSpaceId {
                windowState.selectedShortcutPinForSpace[currentSpaceId] = nil
            }
            return false
        }

        return materialize(pin, in: windowState)
    }

    func materialize(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        activation.commitActivation(
            pin,
            in: windowState.id,
            presentationSpaceID: pin.spaceId ?? windowState.currentSpaceId
        ) { liveTab in
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
}
