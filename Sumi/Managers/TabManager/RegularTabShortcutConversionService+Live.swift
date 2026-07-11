import Foundation

extension RegularTabShortcutConversionService {
    convenience init(tabManager: TabManager) {
        let windows = tabManager.shortcutTabWindowQuery
        let structureTransition = RegularTabShortcutStructureTransition(
            regularTabs: tabManager.regularTabCollectionOwner,
            splitGroupContaining: { [weak tabManager] tabId in
                tabManager?.splitGroupStructureOwner.splitGroup(
                    containing: tabId
                )
            },
            structuralRevision: { [weak tabManager] in
                tabManager?.structuralLookupCoordinator.mutationRevision ?? 0
            },
            upsertSplitGroup: { [weak tabManager] group in
                guard let tabManager else { return }
                tabManager.splitGroupStructureOwner.upsertSplitGroup(
                    group,
                    schedulePersistence: false
                )
            }
        )
        self.init(
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.structuralPersistence
                    .scheduleStructuralPersistence()
            },
            makeShortcutPin: { [weak tabManager] tab, role, profileId, spaceId, folderId, index in
                guard let tabManager else {
                    preconditionFailure(
                        "TabManager dependency used after deallocation"
                    )
                }
                return tabManager.shortcutPinRuntimeResolutionOwner
                    .makeShortcutPin(
                        from: tab,
                        role: role,
                        profileId: profileId,
                        spaceId: spaceId,
                        folderId: folderId,
                        index: index
                    )
            },
            insertShortcutPin: { [weak tabManager] pin, index, opensFolder in
                tabManager?.shortcutPinStoreOwner.insert(
                    pin,
                    at: index,
                    openTargetFolder: opensFolder
                )
            },
            planner: RegularTabShortcutConversionPlanner(
                windows: windows,
                structureTransition: structureTransition,
                runtimePorts: { [weak tabManager] in tabManager?.runtimePorts }
            ),
            authorizer: TabShortcutConversionAuthorizer(windows: windows),
            displayedCommitter: DisplayedTabShortcutConversionCommitter(
                materializer: tabManager.shortcutTabMaterializer,
                containerRemoval: tabManager.shortcutContainerRemovalOwner,
                regularTabs: tabManager.regularTabCollectionOwner,
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            detachedConverter: DetachedTabShortcutConverter(
                tabManager: tabManager
            ),
            structuralLookup: tabManager.structuralLookupCoordinator
        )
    }
}
