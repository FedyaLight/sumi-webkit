import Foundation

@MainActor
struct PreparedSpaceContentRetirement {
    let footprint: SpaceRemovalFootprint
    let tabs: [Tab]
    let runtime: RuntimePortRegistry
}

/// Retires every collection and live runtime scoped to one Space. Removing the
/// Space catalog entry and repairing window state remain the caller's job.
@MainActor
final class SpaceContentRetirementService {
    private let state: TabStateStore
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let splitGroups: SpaceSplitGroupRetirementService
    private let liveShortcutTabs: LiveShortcutTabRegistry
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        state: TabStateStore,
        structuralMutations: TabStructuralCollectionMutationOwner,
        splitGroups: SpaceSplitGroupRetirementService,
        liveShortcutTabs: LiveShortcutTabRegistry,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.state = state
        self.structuralMutations = structuralMutations
        self.splitGroups = splitGroups
        self.liveShortcutTabs = liveShortcutTabs
        self.runtimeTeardown = runtimeTeardown
    }

    func prepare(
        spaceId: UUID,
        using runtime: RuntimePortRegistry
    ) -> PreparedSpaceContentRetirement {
        let inventory = SpaceTabInventory(spaceId: spaceId, state: state)
        let shortcutPinIds = Set(
            state.shortcutPins.spacePinnedPins(for: spaceId).map(\.id)
                + inventory.all.compactMap(\.shortcutPinId)
        )
        let affectedGroupIDs = splitGroups.retireGroups(
            in: spaceId,
            regularTabIDs: inventory.tabIds,
            shortcutPinIDs: shortcutPinIds
        )

        if state.selection.currentTab.map({
            inventory.tabIds.contains($0.id)
        }) == true {
            state.selection.replaceCurrentTab(nil)
        }

        structuralMutations.setTabs([], for: spaceId)
        structuralMutations.setFolders([], for: spaceId)
        structuralMutations.setSpacePinnedShortcuts([], for: spaceId)
        liveShortcutTabs.removeAll(inSpace: spaceId)

        return PreparedSpaceContentRetirement(
            footprint: SpaceRemovalFootprint(
                spaceId: spaceId,
                tabIds: inventory.tabIds,
                shortcutPinIds: shortcutPinIds,
                splitGroupIds: affectedGroupIDs
            ),
            tabs: inventory.all,
            runtime: runtime
        )
    }

    func finish(_ prepared: PreparedSpaceContentRetirement) {
        runtimeTeardown.teardown(prepared.tabs, using: prepared.runtime)
    }
}
