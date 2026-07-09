//
//  TabFolderMutationActions.swift
//  Sumi
//

import SwiftUI

/// Folder open/delete/ungroup mutations that previously lived inline on `TabFolderView`.
@MainActor
struct TabFolderMutationActions {
    let browserContext: SidebarBrowserContext
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry
    let themeContext: ResolvedThemeContext
    let space: Space
    let folderLayoutAnimation: Animation?

    func toggleFolderOpenState(_ folderId: UUID) {
        withAnimation(folderLayoutAnimation) {
            browserContext.tabManager.folderMutationOwner.toggleFolderOpenState(folderId)
        }
    }

    func deleteNestedFolder(_ childFolder: TabFolder) {
        let childCount = browserContext.tabManager.spacePinnedStructureOwner.folderRecursiveChildCount(
            for: childFolder.id,
            in: space.id
        )
        guard childCount == 0 else {
            SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteFolder(
                folderName: childFolder.name,
                childCount: childCount,
                window: windowState.shellWindow(in: windowRegistry),
                themeContext: themeContext,
                onDelete: {
                    mutateFolderContent {
                        browserContext.tabManager.folderMutationOwner.deleteFolder(childFolder.id)
                    }
                }
            )
            return
        }

        mutateFolderContent {
            browserContext.tabManager.folderMutationOwner.deleteFolder(childFolder.id)
        }
    }

    func ungroupNestedFolder(_ childFolder: TabFolder) {
        mutateFolderContent {
            browserContext.tabManager.folderMutationOwner.ungroupFolder(childFolder.id)
        }
    }

    func activateShortcutPin(_ pin: ShortcutPin) {
        let tab = browserContext.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        browserContext.commands.requestUserTabActivation(
            tab,
            windowState
        )
    }

    func mutateFolderContent(_ update: () -> Void) {
        if let animation = folderLayoutAnimation {
            withAnimation(animation, update)
        } else {
            update()
        }
    }
}
