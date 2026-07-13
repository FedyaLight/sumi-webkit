//
//  TabFolderMutationActions.swift
//  Sumi
//

import SwiftUI

/// Folder open/delete/ungroup mutations that previously lived inline on `TabFolderView`.
@MainActor
struct TabFolderMutationActions {
    let browserContext: SidebarBrowserContext
    let pinCommands: SidebarPinFolderCommands
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry
    let themeContext: ResolvedThemeContext
    let space: Space
    let folderLayoutAnimation: Animation?

    func toggleFolderOpenState(_ folderId: UUID) {
        withAnimation(folderLayoutAnimation) {
            _ = pinCommands.toggleFolder(folderId)
        }
    }

    func deleteNestedFolder(_ childFolder: TabFolder) {
        let childCount = pinCommands.recursiveChildCount(
            for: childFolder.id,
            in: space.id
        ) ?? 0
        guard childCount == 0 else {
            SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteFolder(
                folderName: childFolder.name,
                childCount: childCount,
                window: windowState.shellWindow(in: windowRegistry),
                themeContext: themeContext,
                onDelete: {
                    mutateFolderContent {
                        _ = pinCommands.deleteFolder(childFolder.id)
                    }
                }
            )
            return
        }

        mutateFolderContent {
            _ = pinCommands.deleteFolder(childFolder.id)
        }
    }

    func ungroupNestedFolder(_ childFolder: TabFolder) {
        mutateFolderContent {
            _ = pinCommands.ungroupFolder(childFolder.id)
        }
    }

    func activateShortcutPin(_ pin: ShortcutPin) {
        guard let tab = pinCommands.materialize(
            pin,
            in: windowState,
            currentSpaceID: space.id
        ) else { return }
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
