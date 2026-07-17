import Foundation

@MainActor
final class CleanStartupWindowResetTransaction {
    private let windows: WindowRegistry
    private let spaces: TabSpaceCollectionStateOwner
    private let glance: GlanceManager

    init(
        windows: WindowRegistry,
        spaces: TabSpaceCollectionStateOwner,
        glance: GlanceManager
    ) {
        self.windows = windows
        self.spaces = spaces
        self.glance = glance
    }

    var firstRegularWindow: BrowserWindowState? {
        regularWindows.min { $0.id.uuidString < $1.id.uuidString }
    }

    func reset(selectedWindow: BrowserWindowState) {
        for windowState in regularWindows {
            let fallbackSpaceID = resolvedStartupSpace(for: windowState)?.id

            windowState.currentTabId = nil
            windowState.restorationState.restoredSessionWindowID = nil
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            windowState.activeTabForSpace.removeAll()
            windowState.selectionHistory.recentRegularTabIdsBySpace.removeAll()
            windowState.selectedShortcutPinForSpace.removeAll()
            windowState.selectionHistory.recentSelectionItemsBySpace.removeAll()
            windowState.splitSelection = nil
            windowState.restorationState.pendingSplitSelection = nil
            windowState.isShowingEmptyState = windowState === selectedWindow
            windowState.floatingBarPresentationReason = .none
            windowState.presentationState.isFloatingBarVisible = false
            windowState.floatingBarDraftText = ""
            windowState.floatingBarDraftNavigatesCurrentTab = false
            windowState.currentSpaceId = fallbackSpaceID
            windowState.currentProfileId = fallbackSpaceID.flatMap {
                spaces.space(with: $0)?.profileId
            }
            windowState.restorationState.isAwaitingInitialResolution = false
            glance.restoreSession(nil, in: windowState)
            windowState.compositorInvalidation.refresh()
        }
    }

    func resolvedStartupSpace(for windowState: BrowserWindowState) -> Space? {
        if let currentSpaceID = windowState.currentSpaceId,
           let currentSpace = spaces.space(with: currentSpaceID) {
            return currentSpace
        }
        guard let profileID = windowState.currentProfileId else { return nil }
        return spaces.firstSpace(forProfile: profileID)
    }

    private var regularWindows: [BrowserWindowState] {
        windows.allWindows.filter { !$0.isIncognito }
    }
}
