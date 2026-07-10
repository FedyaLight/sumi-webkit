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
    var profileRuntimeStateOwner: TabProfileRuntimeStateOwner { lifecycleOwners.profileRuntimeStateOwner }
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
    var spaceLifecycleOwner: TabSpaceLifecycleOwner { lifecycleOwners.spaceLifecycleOwner }
    var profileAssignments: ProfileAssignmentServices {
        lifecycleOwners.profileAssignments
    }
    var shortcutPinCommandOwner: ShortcutPinCommandOwner { shortcutOwners.shortcutPinCommandOwner }
    var sidebarDragRoutingOwner: SidebarDragOperationRoutingOwner { structureOwners.sidebarDragRoutingOwner }
    var essentialsShortcutPlacementOwner: EssentialsShortcutPlacementOwner {
        shortcutOwners.essentialsShortcutPlacementOwner
    }
    var shortcutPinStoreOwner: ShortcutPinStoreOwner { shortcutOwners.shortcutPinStoreOwner }
    var shortcutPinRuntimeResolutionOwner: ShortcutPinRuntimeResolutionOwner {
        shortcutOwners.shortcutPinRuntimeResolutionOwner
    }
    var shortcutPinConversionOwner: ShortcutPinConversionOwner { shortcutOwners.shortcutPinConversionOwner }
    var shortcutDragOperationOwner: ShortcutDragOperationOwner { shortcutOwners.shortcutDragOperationOwner }
    var shortcutPresentationOwner: TabShortcutPresentationOwner { shortcutOwners.shortcutPresentationOwner }
    var shortcutContainerRemovalOwner: ShortcutContainerRemovalOwner {
        shortcutOwners.shortcutContainerRemovalOwner
    }
    var shortcutLiveTabOwner: ShortcutLiveTabOwner { shortcutOwners.shortcutLiveTabOwner }
    var spaceLauncherProjectionOwner: SpaceLauncherProjectionOwner {
        structureOwners.spaceLauncherProjectionOwner
    }
    var splitGroupRepairOwner: TabManagerSplitGroupRepairOwner { structureOwners.splitGroupRepairOwner }
    var splitGroupStructureOwner: TabSplitGroupStructureOwner { structureOwners.splitGroupStructureOwner }
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
