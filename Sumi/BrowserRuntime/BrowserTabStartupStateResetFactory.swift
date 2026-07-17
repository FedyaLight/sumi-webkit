import Foundation

@MainActor
enum BrowserTabStartupStateResetFactory {
    static func make(
        state: TabStateStore,
        structuralLookup: TabStructuralLookupCoordinator,
        liveShortcutTabs: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection,
        runtimeTeardown: TabRuntimeTeardownService,
        splitGroupMutations: SplitGroupMutationService,
        structuralMutations: TabStructuralCollectionMutationOwner,
        persistence: TabStructuralPersistenceService,
        lazyRestore: TabLazyRestoreCoordinator,
        shortcutRetirement: LiveShortcutTabBatchRetirement
    ) -> TabStartupStateReset {
        TabStartupStateReset(
            structuralLookup: structuralLookup,
            runtimeReset: TabStartupRuntimeResetTransaction(
                state: state,
                liveShortcutTabs: liveShortcutTabs,
                runtimeConnection: runtimeConnection,
                runtimeTeardown: runtimeTeardown
            ),
            splitGroupReset: TabStartupSplitGroupResetTransaction(
                store: state.splitGroups,
                mutations: splitGroupMutations
            ),
            regularCollectionReset:
                TabStartupRegularCollectionResetTransaction(
                    state: state,
                    structuralMutations: structuralMutations,
                    persistence: persistence
                ),
            transientStateReset: TabStartupTransientStateResetTransaction(
                lazyRestore: lazyRestore,
                liveShortcutRetirement: shortcutRetirement
            )
        )
    }
}
