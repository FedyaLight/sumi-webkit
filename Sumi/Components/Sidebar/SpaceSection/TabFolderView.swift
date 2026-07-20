//
//  TabFolderView.swift
//  Sumi
//
//

import Combine
import SumiDomain
import SwiftUI

struct SidebarLiveFolderSnapshot: Equatable {
    let source: SumiLiveFolderSource?
    let items: [SumiLiveFolderItem]
}

struct TabFolderView: View {
    var folder: TabFolder
    let browserContext: SidebarBrowserContext
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let elevatedFolderIds: Set<UUID>
    let isInteractive: Bool
    let parentFolderId: UUID?
    let containerIndex: Int
    let nestingDepth: Int

    @State private var displayedCollapsedProjectionIDs: [UUID] = []

    @Environment(BrowserWindowState.self) private var windowState

    var shortcutPinsInFolder: [ShortcutPin] {
        inventory.folderPinsByFolderID[folder.id] ?? []
    }

    var body: some View {
        let liveFolderManager = browserContext.liveFolderManager
        SidebarScopedSnapshotReader(
            current: {
                liveFolderSnapshot(manager: liveFolderManager)
            },
            changes: liveFolderManager.contentChanges(for: folder.id)
                .map { [liveFolderManager] in
                    liveFolderSnapshot(manager: liveFolderManager)
                }
                .removeDuplicates()
                .eraseToAnyPublisher(),
            isActive: isInteractive
        ) { liveFolderSnapshot in
            SidebarFolderDragSnapshotReader { dragSnapshot in
                SidebarFolderViewProjectionReader(
                    folder: folder,
                    space: space,
                    shortcutPins: shortcutPinsInFolder,
                    inventory: inventory,
                    selection: selection,
                    liveFolderSnapshot: liveFolderSnapshot,
                ) { projection in
                    TabFolderContentView(
                        folder: folder,
                        browserContext: browserContext,
                        space: space,
                        inventory: inventory,
                        selection: selection,
                        pinProjection: pinProjection,
                        pinCommands: pinCommands,
                        pinExecution: pinExecution,
                        folderCommands: folderCommands,
                        spaceLifecycle: spaceLifecycle,
                        displayedCollapsedProjectionIDs: $displayedCollapsedProjectionIDs,
                        elevatedFolderIds: elevatedFolderIds,
                        isInteractive: isInteractive,
                        parentFolderId: parentFolderId,
                        containerIndex: containerIndex,
                        nestingDepth: nestingDepth,
                        projection: projection,
                        dragSnapshot: dragSnapshot
                    )
                        .transaction { transaction in
                            if dragSnapshot.isCompletingDrop {
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
                        }
                }
            }
        }
    }

    private func liveFolderSnapshot(
        manager: SumiLiveFolderManager
    ) -> SidebarLiveFolderSnapshot {
        let source = manager.source(for: folder.id)
        return SidebarLiveFolderSnapshot(
            source: source,
            items: source == nil ? [] : manager.visibleItems(for: folder.id)
        )
    }
}
