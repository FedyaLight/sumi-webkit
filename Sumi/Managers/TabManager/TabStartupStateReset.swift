import Foundation

/// Retires startup-only live tab instances and clears regular collections while
/// preserving spaces, folders, and persisted launcher definitions.
@MainActor
final class TabStartupStateReset {
    private let state: TabStateStore
    private let lazyRestore: TabLazyRestoreCoordinator
    private let persistence: TabStructuralPersistenceService
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let splitGroups: TabSplitGroupStructureOwner
    private let liveShortcutTabs: LiveShortcutTabRegistry
    private let runtimePorts: () -> RuntimePortRegistry?
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        state: TabStateStore,
        lazyRestore: TabLazyRestoreCoordinator,
        persistence: TabStructuralPersistenceService,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        splitGroups: TabSplitGroupStructureOwner,
        liveShortcutTabs: LiveShortcutTabRegistry,
        runtimePorts: @escaping () -> RuntimePortRegistry?,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.state = state
        self.lazyRestore = lazyRestore
        self.persistence = persistence
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
        self.splitGroups = splitGroups
        self.liveShortcutTabs = liveShortcutTabs
        self.runtimePorts = runtimePorts
        self.runtimeTeardown = runtimeTeardown
    }

    func resetRegularTabsAndShortcutLiveInstances() {
        let shortcutTabs = liveShortcutTabs.snapshot.values.flatMap(\.values)
        let regularTabs = state.spaces.spaces.flatMap {
            state.regularTabs.tabs(in: $0.id)
        }
        let closingTabs = shortcutTabs + regularTabs
        let runtime = runtimePorts()
        guard closingTabs.isEmpty || runtime != nil else { return }

        structuralLookup.withTransaction {
            lazyRestore.clear()
            splitGroups.removeSplitGroups(
                containingAny: Set(closingTabs.map(\.id)),
                schedulePersistence: false
            )
            liveShortcutTabs.removeAll()

            for space in state.spaces.spaces {
                structuralMutations.setTabs([], for: space.id)
                if space.activeTabId != nil {
                    space.activeTabId = nil
                    persistence.markSpacesSnapshotDirty()
                }
            }

            state.selection.replaceCurrentTab(nil)
            persistence.scheduleStructuralPersistenceFromMain()
            if let runtime {
                structuralLookup.runAfterCurrentBatch { [runtimeTeardown] in
                    runtimeTeardown.teardown(closingTabs, using: runtime)
                }
            }
        }
    }
}
