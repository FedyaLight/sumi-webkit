//
//  TabStructureOwnerBag.swift
//  Sumi
//
//  Capability bag: structural mutation, membership, split, and drag owners.
//

import Foundation

/// Groups structure-adjacent TabManager owners so they are not peer `lazy var`
/// Owners on the TabManager façade.
@MainActor
final class TabStructureOwnerBag {
    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    private var tm: TabManager { tabManager }

    lazy var folderOpenState = TabFolderOpenStateService(
        folders: tm.folderCollectionStateOwner,
        structuralLookup: structuralLookupCoordinator,
        persistence: tm.structuralPersistence
    )
    lazy var folderMutationOwner = TabFolderMutationOwner(
        dependencies: .live(
            tabManager: tm,
            folderOpenState: folderOpenState
        )
    )
    lazy var regularTabCollectionOwner = RegularTabCollectionOwner(
        tabManager: tm,
        stateOwner: tm.regularTabCollectionStateOwner
    )
    lazy var regularTabDragService = SidebarRegularTabDragService(dependencies: .live(tabManager: tm))
    lazy var lazyRestoreCoordinator = TabLazyRestoreCoordinator(
        spaces: { [weak self] in self?.tm.spaceStateOwner.spaces ?? [] },
        tabsBySpaceSnapshot: { [weak self] in
            self?.tm.regularTabCollectionStateOwner.tabsBySpaceSnapshot() ?? [:]
        },
        resolveTab: { [weak self] id in
            self?.tm.tabCollectionMembershipOwner.tab(for: id)
        }
    )
    lazy var spacePinnedStructureOwner = SpacePinnedStructureOwner(dependencies: .live(tabManager: tm))
    lazy var sidebarDragRouter = SidebarDragOperationRouter(dependencies: .live(tabManager: tm))
    lazy var spaceLauncherProjection = SpaceLauncherProjectionService(tabManager: tm)
    lazy var structuralCollectionStore = TabStructuralCollectionStore(
        regularTabs: tm.regularTabCollectionStateOwner,
        folders: tm.folderCollectionStateOwner,
        shortcutPins: tm.shortcutPinCollectionStateOwner
    )
    lazy var structuralCollectionSnapshots = TabStructuralCollectionSnapshotStore(
        regularTabs: tm.regularTabCollectionStateOwner,
        folders: tm.folderCollectionStateOwner,
        shortcutPins: tm.shortcutPinCollectionStateOwner
    )
    lazy var structuralMutationPublisher = TabStructuralMutationPublisher(
        persistence: tm.structuralPersistence,
        faviconService: tm.faviconService,
        lookup: structuralLookupCoordinator,
        changes: tm.objectWillChange,
        regularTabs: tm.regularTabCollectionStateOwner
    )
    lazy var structuralCollectionMutationOwner = TabStructuralCollectionMutationOwner(
        store: structuralCollectionStore,
        snapshots: structuralCollectionSnapshots,
        publisher: structuralMutationPublisher
    )
    lazy var structuralInstallOwner = TabStructuralInstallOwner(
        dependencies: .live(tabManager: tm)
    )
    lazy var structuralLookupCoordinator = TabStructuralLookupCoordinator(
        eventBus: tm.tabStructureEventBus,
        tabsBySpace: { [weak self] in
            self?.tm.regularTabCollectionStateOwner.tabsBySpaceSnapshot() ?? [:]
        },
        transientShortcutTabsByWindow: { [weak self] in
            self?.tm.transientTabRegistryOwner.transientShortcutTabsByWindow ?? [:]
        },
        transientExtensionTabsByID: { [weak self] in
            self?.tm.transientTabRegistryOwner.transientExtensionTabsByID ?? [:]
        },
        auxiliaryMiniWindowTabsByID: { [weak self] in
            self?.tm.transientTabRegistryOwner.auxiliaryMiniWindowTabsByID ?? [:]
        }
    )
    lazy var tabCollectionMembershipOwner = TabCollectionMembershipOwner(
        tabManager: tm,
        structuralLookupOwner: structuralLookupCoordinator.lookupOwner,
        transientTabRegistryOwner: tm.transientTabRegistryOwner
    )
}
