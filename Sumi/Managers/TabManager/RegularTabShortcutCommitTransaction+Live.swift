extension RegularTabShortcutCommitTransaction {
    static func compose(
        pinStore: ShortcutPinStoreOwner,
        pins: ShortcutPinCollectionStateOwner,
        splitMutations: SplitGroupMutationService,
        structuralMutations: TabStructuralCollectionMutationOwner,
        persistence: TabStructuralPersistenceService,
        folders: TabFolderOpenStateService,
        registry: LiveShortcutTabRegistry,
        membership: TabCollectionMembershipOwner,
        resolution: ShortcutPinRuntimeResolutionOwner,
        tabFactory: TabFactory,
        bindings: ShortcutTabBindingSynchronizer,
        runtimeConnection: TabRuntimePortConnection,
        windowMutations: BrowserWindowShortcutMutationOwner,
        profiles: TabProfileTransitionService,
        structuralLookup: TabStructuralLookupCoordinator,
        windows: ShortcutTabWindowQuery,
        containerRemoval: ShortcutContainerRemovalOwner,
        selection: TabSelectionStateOwner,
        runtimeTeardown: TabRuntimeTeardownService,
        regularTabs: RegularTabCollectionOwner
    ) -> Self {
        let structure = RegularTabShortcutCommitStructurePreparer(
            catalog: ShortcutSplitLauncherCatalogTransaction(
                pinStore: pinStore,
                pins: pins
            ),
            topology: splitMutations,
            structural: structuralMutations
        )
        let terminal = RegularTabShortcutTerminalEffectsFactory(
            persistence: persistence,
            folders: folders
        )
        let batches = ShortcutTabBindingBatchFactory(
            runtimeConnection: runtimeConnection,
            windowMutations: windowMutations,
            profiles: profiles,
            persistence: ShortcutSplitLauncherWindowPersistence(
                structuralLookup: structuralLookup
            ),
            structuralLookup: structuralLookup
        )
        let displayedTransition = DisplayedTabShortcutConversionCommitter(
            bindings: DisplayedTabShortcutBindingPreparer(
                registry: registry,
                membership: membership,
                resolution: resolution,
                freshTabs: ShortcutFreshTabFactory(
                    tabFactory: tabFactory,
                    bindings: bindings
                )
            ),
            batches: batches,
            runtime: DisplayedTabShortcutRuntimePreparer(
                membership: membership,
                containerRemoval: containerRemoval,
                regularTabs: regularTabs,
                structuralLookup: structuralLookup
            )
        )
        let detachedTransition = DetachedTabShortcutConverter(
            batches: batches,
            source: DetachedTabShortcutSourcePreparer(
                windows: windows,
                containerRemoval: containerRemoval,
                membership: membership,
                selection: selection,
                runtimeTeardown: runtimeTeardown
            ),
            windowReconciler: RegularTabShortcutWindowReconciler(
                regularTabs: regularTabs
            )
        )
        return Self(
            displayed: RegularTabShortcutDisplayedCommitter(
                structure: structure,
                transition: displayedTransition,
                terminal: terminal,
                structuralLookup: structuralLookup
            ),
            detached: RegularTabShortcutDetachedCommitter(
                structure: structure,
                transition: detachedTransition,
                terminal: terminal,
                structuralLookup: structuralLookup
            )
        )
    }
}
