//
//  TabManager+OwnerAccessors.swift
//  Sumi
//
//  Thin bag accessors keep call sites on TabManager.*Owner while owners live
//  in Tab*OwnerBag capability bags.
//

import Foundation

extension TabManager {
    var folderMutationOwner: TabFolderMutationOwner { structureOwners.folderMutationOwner }
    var runtimePreparationOwner: TabRuntimePreparationOwner { lifecycleOwners.runtimePreparationOwner }
    var runtimePortsAttachmentOwner: TabRuntimePortsAttachmentOwner {
        lifecycleOwners.runtimePortsAttachmentOwner
    }
    var regularTabCollectionOwner: RegularTabCollectionOwner { structureOwners.regularTabCollectionOwner }
    var regularTabLifecycleOwner: TabRegularLifecycleOwner { lifecycleOwners.regularTabLifecycleOwner }
    var tabRemovalOwner: TabRemovalOwner { lifecycleOwners.tabRemovalOwner }
    var activeSelectionOwner: TabActiveSelectionOwner { lifecycleOwners.activeSelectionOwner }
    var regularTabDragService: SidebarRegularTabDragService { structureOwners.regularTabDragService }
    var lazyRestoreCoordinator: TabLazyRestoreCoordinator { structureOwners.lazyRestoreCoordinator }
    var spacePinnedStructureOwner: SpacePinnedStructureOwner { structureOwners.spacePinnedStructureOwner }
    var profileAssignments: ProfileAssignmentServices {
        lifecycleOwners.profileAssignments
    }
    var shortcutPinCommandOwner: ShortcutPinCommandOwner { shortcutOwners.shortcutPinCommandOwner }
    var sidebarDragRouter: SidebarDragOperationRouter { structureOwners.sidebarDragRouter }
    var essentialsShortcutPlacementOwner: EssentialsShortcutPlacementOwner {
        shortcutOwners.essentialsShortcutPlacementOwner
    }
    var shortcutPinStoreOwner: ShortcutPinStoreOwner { shortcutOwners.shortcutPinStoreOwner }
    var shortcutPinRuntimeResolutionOwner: ShortcutPinRuntimeResolutionOwner {
        shortcutOwners.shortcutPinRuntimeResolutionOwner
    }
    var shortcutDragOperationOwner: ShortcutDragOperationOwner { shortcutOwners.shortcutDragOperationOwner }
    var shortcutPresentationOwner: TabShortcutPresentationOwner { shortcutOwners.shortcutPresentationOwner }
    var shortcutContainerRemovalOwner: ShortcutContainerRemovalOwner {
        shortcutOwners.shortcutContainerRemovalOwner
    }
    var spaceLauncherProjection: SpaceLauncherProjectionService {
        structureOwners.spaceLauncherProjection
    }
    var structuralCollectionMutationOwner: TabStructuralCollectionMutationOwner {
        structureOwners.structuralCollectionMutationOwner
    }
    var structuralInstallOwner: TabStructuralInstallOwner { structureOwners.structuralInstallOwner }
    var tabCollectionMembershipOwner: TabCollectionMembershipOwner {
        structureOwners.tabCollectionMembershipOwner
    }
    var transientWebKitTabLifecycleOwner: TabTransientWebKitTabLifecycleOwner {
        lifecycleOwners.transientWebKitTabLifecycleOwner
    }
    var ephemeralLifecycleOwner: TabEphemeralLifecycleOwner { lifecycleOwners.ephemeralLifecycleOwner }
    var structuralLookupCoordinator: TabStructuralLookupCoordinator {
        structureOwners.structuralLookupCoordinator
    }
}
