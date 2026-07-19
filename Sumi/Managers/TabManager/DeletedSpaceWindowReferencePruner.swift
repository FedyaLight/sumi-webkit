import Foundation

/// Applies one deleted-Space footprint to a single window's durable state.
@MainActor
struct DeletedSpaceWindowReferencePruner {
    func removeReferences(
        to removal: SpaceRemovalFootprint,
        from windowState: BrowserWindowState,
        spaceSurvives: Bool = false
    ) -> Bool {
        var changed = pruneCurrentSelection(
            removal,
            in: windowState,
            spaceSurvives: spaceSurvives
        )

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
        if windowState.sidebarSpacePinnedCollapse.removeSpace(removal.spaceId) {
            changed = true
        }

        var history = windowState.selectionHistory
        if history.removeReferences(
            toSpaceID: removal.spaceId,
            tabIDs: removal.tabIds,
            shortcutPinIDs: removal.shortcutPinIds
        ) {
            windowState.selectionHistory = history
            changed = true
        }
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
        return changed
    }

    private func pruneCurrentSelection(
        _ removal: SpaceRemovalFootprint,
        in windowState: BrowserWindowState,
        spaceSurvives: Bool
    ) -> Bool {
        var changed = false
        if !spaceSurvives, windowState.currentSpaceId == removal.spaceId {
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
}
