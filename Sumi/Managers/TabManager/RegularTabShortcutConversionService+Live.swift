import Foundation

extension RegularTabShortcutConversionService {
    convenience init(tabManager: TabManager) {
        let windows = tabManager.shortcutTabWindowQuery
        let structure = RegularTabShortcutStructureTransition(
            regularTabs: tabManager.regularTabCollectionOwner,
            splitGroupStore: tabManager.splitGroupStore,
            structuralRevision: { [weak tabManager] in
                tabManager?.structuralLookupCoordinator.mutationRevision ?? 0
            }
        )
        let planner = RegularTabShortcutConversionPlanner(
            windows: windows,
            structureTransition: structure,
            runtimePorts: { [weak tabManager] in tabManager?.runtimePorts }
        )
        let candidates = RegularTabShortcutCandidatePreparer(
            planner: planner,
            authorizer: TabShortcutConversionAuthorizer(windows: windows),
            makeShortcutPin: { [weak tabManager] tab, role, profile, space, folder, index in
                guard let tabManager else {
                    preconditionFailure("TabManager deallocated during conversion")
                }
                return tabManager.shortcutPinRuntimeResolutionOwner
                    .makeShortcutPin(
                        from: tab,
                        role: role,
                        profileId: profile,
                        spaceId: space,
                        folderId: folder,
                        index: index
                    )
            }
        )
        let transaction = RegularTabShortcutCommitTransaction(
            schedulePersistence: { [weak tabManager] in
                tabManager?.structuralPersistence.scheduleStructuralPersistence()
            },
            insertPin: { [weak tabManager] pin, index, opensFolder in
                tabManager?.shortcutPinStoreOwner.insert(
                    pin,
                    at: index,
                    openTargetFolder: opensFolder
                )
            },
            removePin: { [weak tabManager] in
                tabManager?.shortcutPinStoreOwner.removeFromContainers($0)
            },
            splitMutations: tabManager.splitGroupMutations,
            structuralLookup: tabManager.structuralLookupCoordinator,
            displayedTransition: DisplayedTabShortcutConversionCommitter(
                materializer: tabManager.shortcutTabMaterializer,
                containerRemoval: tabManager.shortcutContainerRemovalOwner,
                regularTabs: tabManager.regularTabCollectionOwner,
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            detachedTransition: DetachedTabShortcutConverter(
                tabManager: tabManager
            )
        )
        self.init(
            candidates: candidates,
            sidebarCandidates: RegularTabShortcutSidebarCandidatePreparer(
                conversions: candidates
            ),
            replacementValidator: ShortcutSidebarDropReplacementValidator(),
            transaction: transaction
        )
    }
}
