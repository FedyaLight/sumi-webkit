extension RegularTabShortcutCommitTransaction {
    static func live(tabManager: TabManager) -> Self {
        let structure = RegularTabShortcutCommitStructurePreparer(
            catalog: ShortcutSplitLauncherCatalogTransaction(
                pinStore: tabManager.shortcutPinStoreOwner,
                pins: tabManager.shortcutPinCollectionStateOwner
            ),
            topology: tabManager.splitGroupMutations,
            structural: tabManager.structuralCollectionMutationOwner
        )
        let terminal = RegularTabShortcutTerminalEffectsFactory(
            persistence: tabManager.structuralPersistence,
            folders: tabManager.folderOpenState
        )
        let displayedTransition = DisplayedTabShortcutConversionCommitter(
            bindings: DisplayedTabShortcutBindingPreparer(
                registry: tabManager.liveShortcutTabs,
                membership: tabManager.tabCollectionMembershipOwner,
                resolution: tabManager.shortcutPinRuntimeResolutionOwner,
                freshTabs: ShortcutFreshTabFactory(tabManager: tabManager)
            ),
            batches: ShortcutTabBindingBatchFactory(
                runtimeConnection: tabManager.runtimePortConnection,
                windowMutations: tabManager.shortcutWindowMutationOwner,
                profiles: tabManager.profileAssignments.tabs,
                persistence: ShortcutSplitLauncherWindowPersistence(
                    structuralLookup: tabManager.structuralLookupCoordinator
                ),
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            runtime: DisplayedTabShortcutRuntimePreparer(
                membership: tabManager.tabCollectionMembershipOwner,
                containerRemoval: tabManager.shortcutContainerRemovalOwner,
                regularTabs: tabManager.regularTabCollectionOwner,
                structuralLookup: tabManager.structuralLookupCoordinator
            )
        )
        return Self(
            displayed: RegularTabShortcutDisplayedCommitter(
                structure: structure,
                transition: displayedTransition,
                terminal: terminal,
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            detached: RegularTabShortcutDetachedCommitter(
                structure: structure,
                transition: DetachedTabShortcutConverter(
                    tabManager: tabManager
                ),
                terminal: terminal,
                structuralLookup: tabManager.structuralLookupCoordinator
            )
        )
    }
}
