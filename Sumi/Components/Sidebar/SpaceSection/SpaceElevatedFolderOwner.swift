//
//  SpaceElevatedFolderOwner.swift
//  Sumi
//

import Foundation

/// Computes which folder IDs should render elevated for the active selection.
@MainActor
struct SpaceElevatedFolderOwner {
    let inventory: SidebarSpaceInventorySnapshot
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let selection: SidebarWindowSelectionQuery
    let windowState: BrowserWindowState
    let selectionSnapshot: SidebarWindowSelectionSnapshot

    var elevatedFolderIds: Set<UUID> {
        var elevated = Set<UUID>()
        if selection.isCurrent(windowState) {
            for pin in inventory.pinsByID.values
            where selection.runtimeAffordance(
                for: pin,
                liveTab: launcherRuntime.liveTab(for: pin.id),
                in: windowState,
                selection: selectionSnapshot
            ).isSelected {
                elevateAncestors(of: pin.folderId, into: &elevated)
            }
        }

        if let currentTabId = selectionSnapshot.currentTabID {
            for pin in inventory.pinsByID.values {
                if launcherRuntime.liveTab(for: pin.id)?.id == currentTabId {
                    elevateAncestors(of: pin.folderId, into: &elevated)
                }
            }
        }

        if let group = selection.selectedSplitGroup(in: windowState),
           case .shortcutSidebar(
            let groupSpaceID,
            _,
            let folderID,
            _
           ) = group.container,
           groupSpaceID == inventory.spaceID {
            elevateAncestors(
                of: folderID,
                into: &elevated
            )
        }

        return elevated
    }

    private func elevateAncestors(
        of folderId: UUID?,
        into elevated: inout Set<UUID>
    ) {
        var currentFolderId = folderId
        while let folderId = currentFolderId {
            if !elevated.insert(folderId).inserted { break }
            currentFolderId = inventory.folder(id: folderId)?.parentFolderId
        }
    }
}
