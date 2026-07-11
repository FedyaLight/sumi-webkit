import Foundation
import SumiDomain

struct SpaceRemovalFootprint {
    let spaceId: UUID
    let tabIds: Set<UUID>
    let shortcutPinIds: Set<UUID>
    let splitGroupIds: Set<UUID>
}

/// Removes references that generic selection validation cannot discover
/// because they live in per-Space history maps or deferred split state.
@MainActor
final class DeletedSpaceWindowStateReconciler {
    private let runtimePorts: () -> RuntimePortRegistry

    init(runtimePorts: @escaping () -> RuntimePortRegistry) {
        self.runtimePorts = runtimePorts
    }

    func runtimeLease() -> RuntimePortRegistry {
        runtimePorts()
    }

    func reconcile(
        _ removal: SpaceRemovalFootprint,
        using runtime: RuntimePortRegistry
    ) -> [BrowserWindowState] {
        var changedWindows: [BrowserWindowState] = []
        runtime.forEachWindowState { windowState in
            if removeReferences(to: removal, from: windowState) {
                changedWindows.append(windowState)
            }
        }
        return changedWindows.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func finish(
        changedWindows: [BrowserWindowState],
        using runtime: RuntimePortRegistry
    ) {
        let persistedWindowIds = runtime.validateWindowStates()
        changedWindows
            .filter { persistedWindowIds.contains($0.id) == false }
            .forEach(runtime.persistWindowSession(for:))
    }

    private func removeReferences(
        to removal: SpaceRemovalFootprint,
        from windowState: BrowserWindowState
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
        if windowState.currentShortcutPinId
            .map(removal.shortcutPinIds.contains) == true {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            changed = true
        }

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

        cleanSelectionHistory(removal, in: windowState)

        if let request = windowState.pendingSplitGroupFocusRequest,
           request.targetSpaceId == removal.spaceId
            || removal.splitGroupIds.contains(request.groupId) {
            windowState.pendingSplitGroupFocusRequest = nil
            changed = true
        }
        if windowState.pendingSessionSplitGroupId
            .map(removal.splitGroupIds.contains) == true {
            windowState.pendingSessionSplitGroupId = nil
            changed = true
        }
        if let legacyGroup = windowState.pendingSessionLegacySplitGroup,
           legacyGroup.hostSpaceId == removal.spaceId
            || legacyGroup.tabIds.contains(where: removal.tabIds.contains) {
            windowState.pendingSessionLegacySplitGroup = nil
            changed = true
        }
        return changed
    }

    private func cleanSelectionHistory(
        _ removal: SpaceRemovalFootprint,
        in windowState: BrowserWindowState
    ) {
        let history = windowState.selectionHistory
        let previousRegular = history.recentRegularTabIdsBySpace
        history.recentRegularTabIdsBySpace = previousRegular.reduce(into: [:]) { result, entry in
            guard entry.key != removal.spaceId else { return }
            let remaining = entry.value.filter { !removal.tabIds.contains($0) }
            if !remaining.isEmpty { result[entry.key] = remaining }
        }

        let previousSelections = history.recentSelectionItemsBySpace
        history.recentSelectionItemsBySpace = previousSelections.reduce(into: [:]) { result, entry in
            guard entry.key != removal.spaceId else { return }
            let remaining = entry.value.filter { item in
                switch item {
                case .regularTab(let tabId):
                    !removal.tabIds.contains(tabId)
                case .shortcutPin(let pinId):
                    !removal.shortcutPinIds.contains(pinId)
                }
            }
            if !remaining.isEmpty { result[entry.key] = remaining }
        }
    }
}
