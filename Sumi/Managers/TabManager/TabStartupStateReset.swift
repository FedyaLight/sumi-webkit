import Foundation

/// Retires startup-only live tab instances and clears regular collections while
/// preserving spaces, folders, and persisted launcher definitions.
@MainActor
final class TabStartupStateReset {
    private let runtimePorts: () -> RuntimePortRegistry
    private let state: TabStateStore
    private let lazyRestore: TabLazyRestoreCoordinator
    private let persistence: TabStructuralPersistenceService
    private let membership: TabCollectionMembershipOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        runtimePorts: @escaping () -> RuntimePortRegistry,
        state: TabStateStore,
        lazyRestore: TabLazyRestoreCoordinator,
        persistence: TabStructuralPersistenceService,
        membership: TabCollectionMembershipOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.runtimePorts = runtimePorts
        self.state = state
        self.lazyRestore = lazyRestore
        self.persistence = persistence
        self.membership = membership
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
    }

    convenience init(
        runtimePortsProvider: @escaping () -> RuntimePortRegistry?,
        state: TabStateStore,
        lazyRestore: TabLazyRestoreCoordinator,
        persistence: TabStructuralPersistenceService,
        membership: TabCollectionMembershipOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.init(
            runtimePorts: {
                guard let runtimePorts = runtimePortsProvider() else {
                    preconditionFailure(
                        "Startup tab reset requires attached runtime ports"
                    )
                }
                return runtimePorts
            },
            state: state,
            lazyRestore: lazyRestore,
            persistence: persistence,
            membership: membership,
            structuralMutations: structuralMutations,
            structuralLookup: structuralLookup
        )
    }

    func resetRegularTabsAndShortcutLiveInstances() {
        let webViews = runtimePorts().webViewLifecycle
        structuralLookup.withTransaction {
            lazyRestore.clear()

            let liveShortcutTabs = state.transientTabs.transientShortcutTabs
            for tab in liveShortcutTabs {
                persistence.cancelRuntimeStatePersistence(for: tab.id)
                tab.performComprehensiveWebViewCleanup()
                webViews.unloadTab(tab)
                webViews.requireRemoveAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: true
                )
                membership.detach(tab)
            }
            if !liveShortcutTabs.isEmpty {
                state.transientTabs.replaceTransientShortcutTabsByWindow([:])
                structuralLookup.notifyTransientShortcutStateChanged()
            }

            for space in state.spaces.spaces {
                for tab in state.regularTabs.tabs(in: space.id) {
                    persistence.cancelRuntimeStatePersistence(for: tab.id)
                    webViews.unloadTab(tab)
                    webViews.requireRemoveAllWebViews(
                        for: tab,
                        closeActiveFullscreenMedia: true
                    )
                    membership.detach(tab)
                }
                structuralMutations.setTabs([], for: space.id)
                if space.activeTabId != nil {
                    space.activeTabId = nil
                    persistence.markSpacesSnapshotDirty()
                }
            }

            state.selection.replaceCurrentTab(nil)
            persistence.scheduleStructuralPersistenceFromMain()
        }
    }
}
