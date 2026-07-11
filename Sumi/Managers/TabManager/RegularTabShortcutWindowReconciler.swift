import Foundation

/// Repairs every window reference after a regular tab becomes a shortcut.
/// Displaying windows receive their exact live instance; other windows only
/// lose stale regular-tab selection memory.
@MainActor
final class RegularTabShortcutWindowReconciler {
    private let regularTabs: RegularTabCollectionOwner

    init(regularTabs: RegularTabCollectionOwner) {
        self.regularTabs = regularTabs
    }

    func reconcile(
        originalTabId: UUID,
        sourceSpaceId: UUID?,
        liveTabsByWindowId: [UUID: Tab],
        selectedWindowIds: Set<UUID>,
        using runtime: RuntimePortRegistry
    ) -> [BrowserWindowState] {
        var changedStates: [UUID: BrowserWindowState] = [:]
        runtime.forEachWindow { windowId, windowState in
            if DisplayedTabShortcutWindowTransition.apply(
                to: windowState,
                originalTabId: originalTabId,
                liveTab: liveTabsByWindowId[windowId],
                sourceSpaceId: sourceSpaceId,
                isSelected: selectedWindowIds.contains(windowId),
                regularTabs: regularTabs
            ) {
                changedStates[windowId] = windowState
            }
        }
        return changedStates.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }
}
