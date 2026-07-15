@MainActor
extension ShortcutLiveTabRetirementService {
    convenience init(tabManager: TabManager) {
        self.init(
            registry: tabManager.liveShortcutTabs,
            structuralLookup: tabManager.structuralLookupCoordinator,
            runtimeConnection: tabManager.runtimePortConnection,
            runtimeTeardown: tabManager.runtimeTeardown,
            windowMutations: tabManager.shortcutWindowMutationOwner,
            splitGroups: tabManager.splitGroupStore,
            splitMutations: tabManager.splitGroupMutations
        )
    }
}
