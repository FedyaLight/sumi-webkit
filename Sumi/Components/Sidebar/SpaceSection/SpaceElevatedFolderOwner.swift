//
//  SpaceElevatedFolderOwner.swift
//  Sumi
//

import Foundation

/// Computes which folder IDs should render elevated for the active selection.
@MainActor
struct SpaceElevatedFolderOwner {
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let windowState: BrowserWindowState

    var elevatedFolderIds: Set<UUID> {
        var elevated = Set<UUID>()
        if selection.isCurrent(windowState) {
            for pin in inventory.pinsByID.values
            where selection.isShortcutSelected(pin, in: windowState) {
                elevateAncestors(of: pin.folderId, into: &elevated)
            }
        }

        if let currentTabId = selection.selectedTabID(in: windowState) {
            for pin in inventory.pinsByID.values {
                if selection.liveTab(for: pin.id, in: windowState)?.id == currentTabId {
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
