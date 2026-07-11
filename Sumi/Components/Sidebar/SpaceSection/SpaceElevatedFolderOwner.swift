//
//  SpaceElevatedFolderOwner.swift
//  Sumi
//

import Foundation

/// Computes which folder IDs should render elevated for the active selection.
@MainActor
struct SpaceElevatedFolderOwner {
    let browserContext: SidebarBrowserContext
    let space: Space
    let windowState: BrowserWindowState

    var elevatedFolderIds: Set<UUID> {
        var elevated = Set<UUID>()
        let tabManager = browserContext.tabManager

        if let currentShortcutPinId = windowState.currentShortcutPinId {
            if let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: currentShortcutPinId),
               pin.spaceId == space.id {
                elevateAncestors(of: pin.folderId, into: &elevated, tabManager: tabManager)
            }
        }

        if let currentTabId = windowState.currentTabId {
            let allPins = tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id)
            for pin in allPins {
                if tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id)?.id == currentTabId {
                    elevateAncestors(of: pin.folderId, into: &elevated, tabManager: tabManager)
                }
            }

        }

        if let selectedGroupID = windowState.splitSelection?.groupID,
           let group = tabManager.splitGroupStore.group(id: selectedGroupID),
           case .shortcutSidebar(
            let groupSpaceID,
            _,
            let folderID,
            _
           ) = group.container,
           groupSpaceID == space.id {
            elevateAncestors(
                of: folderID,
                into: &elevated,
                tabManager: tabManager
            )
        }

        return elevated
    }

    private func elevateAncestors(
        of folderId: UUID?,
        into elevated: inout Set<UUID>,
        tabManager: TabManager
    ) {
        var currentFolderId = folderId
        while let folderId = currentFolderId {
            if !elevated.insert(folderId).inserted { break }
            currentFolderId = tabManager.folderCollectionStateOwner.folder(by: folderId)?.parentFolderId
        }
    }
}
