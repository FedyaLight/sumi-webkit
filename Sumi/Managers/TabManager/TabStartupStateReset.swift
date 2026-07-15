import Foundation
import SumiDomain

/// Retires startup-only live tab instances and clears regular collections while
/// preserving spaces, folders, and persisted launcher definitions.
@MainActor
final class TabStartupStateReset {
    private let state: TabStateStore
    private let lazyRestore: TabLazyRestoreCoordinator
    private let persistence: TabStructuralPersistenceService
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let splitGroupStore: SplitGroupStore
    private let splitGroupMutations: SplitGroupMutationService
    private let liveShortcutTabs: LiveShortcutTabRegistry
    private let liveShortcutRetirement: LiveShortcutTabBatchRetirement
    private let runtimePorts: () -> RuntimePortRegistry?
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        state: TabStateStore,
        lazyRestore: TabLazyRestoreCoordinator,
        persistence: TabStructuralPersistenceService,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        splitGroupStore: SplitGroupStore,
        splitGroupMutations: SplitGroupMutationService,
        liveShortcutTabs: LiveShortcutTabRegistry,
        liveShortcutRetirement: LiveShortcutTabBatchRetirement,
        runtimePorts: @escaping () -> RuntimePortRegistry?,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.state = state
        self.lazyRestore = lazyRestore
        self.persistence = persistence
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
        self.splitGroupStore = splitGroupStore
        self.splitGroupMutations = splitGroupMutations
        self.liveShortcutTabs = liveShortcutTabs
        self.liveShortcutRetirement = liveShortcutRetirement
        self.runtimePorts = runtimePorts
        self.runtimeTeardown = runtimeTeardown
    }

    func resetRegularTabsAndShortcutLiveInstances() {
        let shortcutTabs = liveShortcutTabs.snapshot.values.flatMap(\.values)
        let regularTabs = state.spaces.spaces.flatMap {
            state.regularTabs.tabs(in: $0.id)
        }
        let closingTabs = shortcutTabs + regularTabs
        let preparedTeardown: PreparedTabRuntimeTeardown?
        if closingTabs.isEmpty {
            preparedTeardown = nil
        } else {
            guard let runtime = runtimePorts(),
                  let prepared = runtimeTeardown.preparation.prepare(
                      closingTabs,
                      using: runtime
                  ) else { return }
            preparedTeardown = prepared
        }

        structuralLookup.withTransaction {
            lazyRestore.clear()
            let regularTabIDs = Set(regularTabs.map(\.id))
            let currentGroups = splitGroupStore.groups
            let updatedGroups = currentGroups.compactMap {
                group -> SumiDomain.SplitGroup? in
                let removedMemberIDs = group.memberIDs.filter {
                    guard case .regularTab(let tabID) = $0 else {
                        return false
                    }
                    return regularTabIDs.contains(tabID)
                }
                return removedMemberIDs.reduce(Optional(group)) {
                    $0?.removingMember($1)
                }
            }
            if updatedGroups != currentGroups {
                precondition(
                    splitGroupMutations.replaceAll(
                        expected: currentGroups,
                        with: updatedGroups,
                        persist: false
                    ),
                    "Startup reset lost its exact split-group snapshot"
                )
            }
            _ = liveShortcutRetirement.removeAll()

            for space in state.spaces.spaces {
                structuralMutations.setTabs([], for: space.id)
                if space.activeTabId != nil {
                    space.activeTabId = nil
                    persistence.markSpacesSnapshotDirty()
                }
            }

            state.selection.replaceCurrentTab(nil)
            persistence.scheduleStructuralPersistenceFromMain()
            if let preparedTeardown {
                structuralLookup.runAfterCurrentBatch { [runtimeTeardown] in
                    runtimeTeardown.finish(preparedTeardown)
                }
            }
        }
    }
}
