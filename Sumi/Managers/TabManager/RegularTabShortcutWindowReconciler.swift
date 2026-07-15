import Foundation
import SumiDomain

/// Repairs every window reference after a regular tab becomes a shortcut.
/// Displaying windows receive their exact live instance; other windows only
/// lose stale regular-tab selection memory.
@MainActor
final class RegularTabShortcutWindowReconciler {
    private let regularTabs: RegularTabCollectionOwner

    init(regularTabs: RegularTabCollectionOwner) {
        self.regularTabs = regularTabs
    }

    func prepareContribution(
        originalTabId: UUID,
        splitTransition: RegularTabShortcutWindowTransitionPlan,
        sourceSpaceId: UUID?,
        liveTabsByWindowId: [UUID: Tab],
        terminalIdentitiesByWindowId: [UUID: ShortcutBindingIdentity],
        selectedWindowIds: Set<UUID>,
        using runtime: RuntimePortRegistry
    ) -> ShortcutTabBindingWindowContribution? {
        guard Set(liveTabsByWindowId.keys)
                == Set(terminalIdentitiesByWindowId.keys) else { return nil }
        var terminalSelectionsByWindowID:
            [UUID: DisplayedTabShortcutTerminalSelectionPlan] = [:]
        for (windowID, tab) in liveTabsByWindowId {
            guard let identity = terminalIdentitiesByWindowId[windowID]
            else { return nil }
            terminalSelectionsByWindowID[windowID] = .init(
                tab: tab,
                identity: identity
            )
        }
        let fallbackRegularTabID = sourceSpaceId.flatMap { spaceID in
            regularTabs.tabs(in: spaceID).first {
                $0.id != originalTabId
            }?.id
        }
        var entries: [ShortcutTabBindingWindowContribution.Entry] = []
        runtime.forEachWindow { windowId, windowState in
            let source = windowState.unpublishedShortcutMutationState
            var target = source
            let requiresPersistence = DisplayedTabShortcutWindowTransition.apply(
                to: &target,
                originalTabId: originalTabId,
                splitTransition: splitTransition,
                terminalSelection: terminalSelectionsByWindowID[windowId],
                sourceSpaceId: sourceSpaceId,
                isSelected: selectedWindowIds.contains(windowId),
                fallbackRegularTabID: fallbackRegularTabID
            )
            entries.append(.init(
                window: windowState,
                source: source,
                target: target,
                requiresPersistence: requiresPersistence
            ))
        }
        return ShortcutTabBindingWindowContribution(entries: entries)
    }
}
