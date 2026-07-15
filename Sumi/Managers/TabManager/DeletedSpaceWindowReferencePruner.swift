import Foundation

/// Applies one deleted-Space footprint to a single window's durable state.
@MainActor
struct DeletedSpaceWindowReferencePruner {
    func removeReferences(
        to removal: SpaceRemovalFootprint,
        from windowState: BrowserWindowState
    ) -> Bool {
        var changed = pruneCurrentSelection(removal, in: windowState)

        let activeTabs = windowState.activeTabForSpace.filter {
            $0.key != removal.spaceId && !removal.tabIds.contains($0.value)
        }
        if activeTabs != windowState.activeTabForSpace {
            windowState.activeTabForSpace = activeTabs
            changed = true
        }
        let activeShortcuts = windowState.selectedShortcutPinForSpace.filter {
            $0.key != removal.spaceId
                && !removal.shortcutPinIds.contains($0.value)
        }
        if activeShortcuts != windowState.selectedShortcutPinForSpace {
            windowState.selectedShortcutPinForSpace = activeShortcuts
            changed = true
        }

        changed = pruneSelectionHistory(removal, in: windowState) || changed
        if let request = windowState.presentationState.pendingSplitGroupFocusRequest,
           request.targetSpaceID == removal.spaceId
            || removal.splitGroupIds.contains(request.groupID) {
            windowState.presentationState.pendingSplitGroupFocusRequest = nil
            changed = true
        }
        if windowState.splitSelection
            .map({ removal.splitGroupIds.contains($0.groupID) }) == true {
            windowState.splitSelection = nil
            changed = true
        }
        if windowState.restorationState.pendingSplitSelection
            .map({ removal.splitGroupIds.contains($0.groupID) }) == true {
            windowState.restorationState.pendingSplitSelection = nil
            changed = true
        }
        if legacySplitReferencesRemoval(windowState, removal: removal) {
            windowState.restorationState.pendingLegacySplitGroup = nil
            changed = true
        }
        return changed
    }

    private func pruneCurrentSelection(
        _ removal: SpaceRemovalFootprint,
        in windowState: BrowserWindowState
    ) -> Bool {
        var changed = false
        if windowState.currentSpaceId == removal.spaceId {
            windowState.currentSpaceId = nil
            changed = true
        }
        if windowState.currentTabId.map(removal.tabIds.contains) == true {
            windowState.currentTabId = nil
            changed = true
        }
        let retiredWindowPinIDs = removal.retiredShortcutPinIDsByWindow[
            windowState.id
        ] ?? []
        if windowState.currentShortcutPinId.map({
            removal.shortcutPinIds.contains($0)
                || retiredWindowPinIDs.contains($0)
        }) == true {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            changed = true
        }
        return changed
    }

    private func legacySplitReferencesRemoval(
        _ windowState: BrowserWindowState,
        removal: SpaceRemovalFootprint
    ) -> Bool {
        guard let group = windowState.restorationState.pendingLegacySplitGroup else {
            return false
        }
        return group.container.spaceId == removal.spaceId
            || group.memberIDs.contains { memberID in
                switch memberID {
                case .regularTab(let tabID):
                    return removal.tabIds.contains(tabID)
                case .shortcutPin(let pinID):
                    return removal.shortcutPinIds.contains(pinID)
                }
            }
    }

    private func pruneSelectionHistory(
        _ removal: SpaceRemovalFootprint,
        in windowState: BrowserWindowState
    ) -> Bool {
        var history = windowState.selectionHistory
        let previousRegularTabs = history.recentRegularTabIdsBySpace
        let previousSelections = history.recentSelectionItemsBySpace
        history.recentRegularTabIdsBySpace = history.recentRegularTabIdsBySpace
            .reduce(into: [:]) { result, entry in
                guard entry.key != removal.spaceId else { return }
                let remaining = entry.value.filter {
                    !removal.tabIds.contains($0)
                }
                if !remaining.isEmpty { result[entry.key] = remaining }
            }
        history.recentSelectionItemsBySpace = history
            .recentSelectionItemsBySpace.reduce(into: [:]) { result, entry in
                guard entry.key != removal.spaceId else { return }
                let remaining = entry.value.filter { item in
                    switch item {
                    case .regularTab(let tabID):
                        return !removal.tabIds.contains(tabID)
                    case .shortcutPin(let pinID):
                        return !removal.shortcutPinIds.contains(pinID)
                    }
                }
                if !remaining.isEmpty { result[entry.key] = remaining }
            }
        let didChange = history.recentRegularTabIdsBySpace != previousRegularTabs
            || history.recentSelectionItemsBySpace != previousSelections
        if didChange {
            windowState.selectionHistory = history
        }
        return didChange
    }
}
