//
//  TabFolderMutationActions.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Folder open/delete/ungroup mutations used by flattened folder rows.
@MainActor
struct TabFolderMutationActions {
    let browserContext: SidebarBrowserContext
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry
    let themeContext: ResolvedThemeContext
    let space: Space
    let folderLayoutAnimation: Animation?

    func toggleFolderOpenState(_ folderId: UUID) {
        _ = folderCommands.toggleFolder(folderId)
    }

    func deleteNestedFolder(_ childFolder: TabFolder) {
        if childFolder.isLiveFolder {
            mutateFolderContent {
                _ = folderCommands.deleteFolder(childFolder.id)
            }
            return
        }
        let childCount = folderCommands.recursiveChildCount(
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
                        _ = folderCommands.deleteFolder(childFolder.id)
                    }
                }
            )
            return
        }

        mutateFolderContent {
            _ = folderCommands.deleteFolder(childFolder.id)
        }
    }

    func ungroupNestedFolder(_ childFolder: TabFolder) {
        mutateFolderContent {
            _ = folderCommands.ungroupFolder(childFolder.id)
        }
    }

    func activateShortcutPin(_ pin: ShortcutPin) {
        guard let tab = pinExecution.materialize(
            pin,
            in: windowState,
            currentSpaceID: space.id
        ) else { return }
        browserContext.tabSelection.requestUserTabActivation(
            tab,
            in: windowState,
            loadPolicy: .immediate
        )
    }

    /// Zen parity for the collapsed-folder reset affordance: unloads every
    /// live launcher inside the folder and clears the sticky sets of the
    /// folder and every descendant folder, fully re-collapsing the row.
    func resetCollapsedProjection(
        _ folder: TabFolder,
        inventory: SidebarSpaceInventorySnapshot
    ) {
        let projections = windowState.sidebarFolderProjections
        var folderIDsToClear = [folder.id]
        var visited = Set<UUID>()

        func collectDescendantFolders(_ parentID: UUID) {
            guard visited.insert(parentID).inserted else { return }
            for child in inventory.childFoldersByParentID[parentID] ?? [] {
                folderIDsToClear.append(child.id)
                collectDescendantFolders(child.id)
            }
        }
        collectDescendantFolders(folder.id)

        for group in inventory.descendantSplitGroups(for: folder.id) {
            browserContext.splitGroupLifecycle.unload(group, in: windowState)
        }

        let descendantPins = inventory.descendantPins(for: folder.id)
        if !descendantPins.isEmpty {
            browserContext.shortcutPinUnload.unloadShortcutPins(
                descendantPins,
                in: windowState
            )
        }
        mutateFolderContent {
            for folderID in folderIDsToClear {
                projections.scheduleMutation(for: folderID) { _ in .empty }
            }
        }
    }

    func focusSplitGroup(_ groupID: UUID, memberID: SplitMemberID) {
        browserContext.splitFocusCommands.focusGroup(
            groupID,
            memberID,
            windowState.id
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
