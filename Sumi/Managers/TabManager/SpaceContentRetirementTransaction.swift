import Foundation

/// Owns the structural commit for one Space after physical teardown has been
/// prepared. It revalidates exact tab identity before changing any collection.
@MainActor
final class SpaceContentRetirementTransaction {
    private let state: TabStateStore
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let splitGroups: SpaceSplitGroupRetirementService
    private let liveShortcutTabs: LiveShortcutTabRegistry

    init(
        state: TabStateStore,
        structuralMutations: TabStructuralCollectionMutationOwner,
        splitGroups: SpaceSplitGroupRetirementService,
        liveShortcutTabs: LiveShortcutTabRegistry
    ) {
        self.state = state
        self.structuralMutations = structuralMutations
        self.splitGroups = splitGroups
        self.liveShortcutTabs = liveShortcutTabs
    }

    func inventory(spaceId: UUID) -> SpaceTabInventory {
        SpaceTabInventory(spaceId: spaceId, state: state)
    }

    func commit(
        _ plan: PlannedSpaceContentRetirement
    ) -> SpaceRemovalFootprint? {
        let inventory = inventory(spaceId: plan.spaceId)
        guard inventory.all.count == plan.tabs.count,
              zip(inventory.all, plan.tabs).allSatisfy({ $0 === $1 }) else {
            return nil
        }
        let shortcutPinIds = Set(
            state.shortcutPins.spacePinnedPins(for: plan.spaceId).map(\.id)
                + inventory.all.compactMap(\.shortcutPinId)
        )
        let affectedGroupIDs = splitGroups.retireGroups(
            in: plan.spaceId,
            regularTabIDs: inventory.tabIds,
            shortcutPinIDs: shortcutPinIds
        )
        if state.selection.currentTab.map({
            inventory.tabIds.contains($0.id)
        }) == true {
            state.selection.replaceCurrentTab(nil)
        }
        structuralMutations.setTabs([], for: plan.spaceId)
        structuralMutations.setFolders([], for: plan.spaceId)
        structuralMutations.setSpacePinnedShortcuts([], for: plan.spaceId)
        liveShortcutTabs.removeAll(inSpace: plan.spaceId)
        return SpaceRemovalFootprint(
            spaceId: plan.spaceId,
            tabIds: inventory.tabIds,
            shortcutPinIds: shortcutPinIds,
            splitGroupIds: affectedGroupIDs
        )
    }
}
