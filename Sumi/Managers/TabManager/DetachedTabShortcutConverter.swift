import Foundation

/// Replaces a regular tab that is not displayed by any browser window with a
/// durable shortcut definition. It deliberately creates no live shortcut tab;
/// a window materializes one later when the launcher is activated.
@MainActor
final class DetachedTabShortcutConverter {
    private let regularTabs: RegularTabCollectionOwner
    private let containerRemoval: ShortcutContainerRemovalOwner
    private let membership: TabCollectionMembershipOwner
    private let selection: TabSelectionStateOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeTeardown: TabRuntimeTeardownService
    private let windowReconciler: RegularTabShortcutWindowReconciler

    init(
        regularTabs: RegularTabCollectionOwner,
        containerRemoval: ShortcutContainerRemovalOwner,
        membership: TabCollectionMembershipOwner,
        selection: TabSelectionStateOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.regularTabs = regularTabs
        self.containerRemoval = containerRemoval
        self.membership = membership
        self.selection = selection
        self.structuralLookup = structuralLookup
        self.runtimeTeardown = runtimeTeardown
        windowReconciler = RegularTabShortcutWindowReconciler(
            regularTabs: regularTabs
        )
    }

    convenience init(tabManager: TabManager) {
        self.init(
            regularTabs: tabManager.regularTabCollectionOwner,
            containerRemoval: tabManager.shortcutContainerRemovalOwner,
            membership: tabManager.tabCollectionMembershipOwner,
            selection: tabManager.selectionStateOwner,
            structuralLookup: tabManager.structuralLookupCoordinator,
            runtimeTeardown: tabManager.runtimeTeardown
        )
    }

    func commit(
        using authorization: AuthorizedDetachedTabShortcutConversion
    ) {
        let tab = authorization.tab
        let runtime = authorization.runtime

        containerRemoval.removeFromCurrentContainer(tab)
        membership.detach(tab)
        if selection.currentTab === tab {
            selection.replaceCurrentTab(nil)
        }
        if let runtime {
            let changedWindows = windowReconciler.reconcile(
                originalTabId: tab.id,
                sourceSpaceId: tab.spaceId,
                liveTabsByWindowId: [:],
                selectedWindowIds: [],
                using: runtime
            )
            structuralLookup.runAfterCurrentBatch { [runtimeTeardown] in
                runtimeTeardown.teardown([tab], using: runtime)
                changedWindows.forEach(runtime.persistWindowSession(for:))
            }
        }
    }
}
