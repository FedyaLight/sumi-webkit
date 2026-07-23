import Foundation

@MainActor
final class CleanStartupWindowResetTransaction {
    private let windows: WindowRegistry
    private let spaces: TabSpaceCollectionStateOwner
    private let glance: GlanceManager
    private let currentProfileID: @MainActor () -> UUID?

    init(
        windows: WindowRegistry,
        spaces: TabSpaceCollectionStateOwner,
        glance: GlanceManager,
        currentProfileID: @escaping @MainActor () -> UUID?
    ) {
        self.windows = windows
        self.spaces = spaces
        self.glance = glance
        self.currentProfileID = currentProfileID
    }

    var firstRegularWindow: BrowserWindowState? {
        regularWindows.min { $0.id.uuidString < $1.id.uuidString }
    }

    func reset(selectedWindow: BrowserWindowState) {
        for windowState in regularWindows {
            let fallbackSpaceID = resolvedWindowResetSpace(
                for: windowState
            )?.id

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
            windowState.commandPalettePresentationReason = .none
            windowState.presentationState.isCommandPaletteVisible = false
            windowState.commandPaletteDraftText = ""
            windowState.commandPaletteDraftNavigatesCurrentTab = false
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
        if let profileID = windowState.currentProfileId {
            return spaces.firstSpace(forProfile: profileID)
        }

        return nil
    }

    private func resolvedWindowResetSpace(
        for windowState: BrowserWindowState
    ) -> Space? {
        if let resolved = resolvedStartupSpace(for: windowState) {
            return resolved
        }
        guard windowState.currentSpaceId == nil,
              windowState.currentProfileId == nil
        else { return nil }
        if let currentSpace = spaces.currentSpace,
           let catalogSpace = spaces.space(with: currentSpace.id) {
            return catalogSpace
        }
        guard let profileID = currentProfileID() else { return nil }
        return spaces.firstSpace(forProfile: profileID)
    }

    private var regularWindows: [BrowserWindowState] {
        windows.allWindows.filter { !$0.isIncognito }
    }
}
