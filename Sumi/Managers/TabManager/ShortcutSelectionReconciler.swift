import Foundation

/// Removes window-local references to a retired shortcut instance or deleted
/// shortcut pin. Runtime ownership and registry mutation live elsewhere.
@MainActor
enum ShortcutSelectionReconciler {
    static func reconcileRetiredInstance(
        pinId: UUID,
        tabId: UUID,
        in windowState: BrowserWindowState
    ) -> ShortcutLiveTabRetirementResult {
        reconcile(
            pinId: pinId,
            retiredTabId: tabId,
            removeRememberedSelection: false,
            in: windowState
        )
    }

    static func reconcileDeletedPin(
        _ pinId: UUID,
        in windowState: BrowserWindowState
    ) -> ShortcutLiveTabRetirementResult {
        reconcile(
            pinId: pinId,
            retiredTabId: nil,
            removeRememberedSelection: true,
            in: windowState
        )
    }

    private static func reconcile(
        pinId: UUID,
        retiredTabId: UUID?,
        removeRememberedSelection: Bool,
        in windowState: BrowserWindowState
    ) -> ShortcutLiveTabRetirementResult {
        let didClearCurrentSelection = ShortcutSelectionIdentity.isSelected(
            tabId: retiredTabId,
            pinId: pinId,
            in: windowState
        )
        var didChangePersistedState = false

        if let retiredTabId, windowState.currentTabId == retiredTabId {
            windowState.currentTabId = nil
            didChangePersistedState = true
        }
        if windowState.currentTabId == pinId {
            windowState.currentTabId = nil
            didChangePersistedState = true
        }
        if windowState.currentShortcutPinId == pinId {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            didChangePersistedState = true
        }
        if removeRememberedSelection {
            let staleSpaceIds = windowState.selectedShortcutPinForSpace
                .compactMap { spaceId, selectedPinId in
                    selectedPinId == pinId ? spaceId : nil
                }
            for spaceId in staleSpaceIds {
                windowState.selectedShortcutPinForSpace.removeValue(forKey: spaceId)
            }
            didChangePersistedState = didChangePersistedState
                || staleSpaceIds.isEmpty == false
        }
        if removeRememberedSelection {
            windowState.selectionHistory
                .removeFromShortcutLiveSelectionHistory(pinId)
        }

        return ShortcutLiveTabRetirementResult(
            didClearCurrentSelection: didClearCurrentSelection,
            windowStatesNeedingPersistence: didChangePersistedState
                ? [windowState]
                : []
        )
    }
}
