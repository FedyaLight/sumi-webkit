//
//  TabFolderView.swift
//  Sumi
//
//

import SumiDomain
import SwiftUI

struct TabFolderView: View {
    var folder: TabFolder
    let browserContext: SidebarBrowserContext
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let shortcutPins: [ShortcutPin]
    let childFolders: [TabFolder]
    let childFoldersByParentId: [UUID: [TabFolder]]
    let folderPinsByFolderId: [UUID: [ShortcutPin]]
    @Binding var shortcutRestoreGaps: [ShortcutRestoreGap]
    @Binding var shortcutRestoreAppearingGapIds: Set<UUID>
    let elevatedFolderIds: Set<UUID>
    let renderMode: SpaceViewRenderMode
    let parentFolderId: UUID?
    let containerIndex: Int
    let nestingDepth: Int
    let onUngroup: () -> Void
    let onDelete: () -> Void
    let onPrepareShortcutRestoreGap: (UUID, SplitMemberID) -> Void
    let onPerformShortcutRestoreWithPreparedGap: (
        UUID,
        SplitMemberID,
        @escaping () -> Void
    ) -> Void

    @State var displayedCollapsedProjectionIDs: [UUID] = []

    @Environment(BrowserWindowState.self) var windowState
    @Environment(WindowRegistry.self) var windowRegistry
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @EnvironmentObject var dragState: SidebarDragState

    var folderDragSnapshot: SidebarFolderDragSnapshot {
        SidebarFolderDragSnapshot(dragState: dragState)
    }

    var isInteractive: Bool {
        renderMode.isInteractive
    }

    var shortcutPinsInFolder: [ShortcutPin] {
        shortcutPins
    }

    var folderProjectionState: SidebarFolderProjectionState {
        windowState.sidebarFolderProjections.projection(for: folder.id)
    }

    var folderLayoutAnimation: Animation? {
        folderDragSnapshot.allowsLayoutAnimation(isInteractive: isInteractive)
            ? SidebarMotionPolicy.folderLayoutAnimation(
                for: SidebarMotionPolicy.currentMode(
                    reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
                )
            )
            : nil
    }

    var mutationActions: TabFolderMutationActions {
        TabFolderMutationActions(
            browserContext: browserContext,
            pinCommands: pinCommands,
            windowState: windowState,
            windowRegistry: windowRegistry,
            themeContext: themeContext,
            space: space,
            folderLayoutAnimation: folderLayoutAnimation
        )
    }

    var contextMenuActionOwner: TabFolderContextMenuActionOwner {
        TabFolderContextMenuActionOwner(
            folder: folder,
            space: space,
            childFoldersByParentId: childFoldersByParentId,
            folderPinsByFolderId: folderPinsByFolderId,
            browserContext: browserContext,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            spaceLifecycle: spaceLifecycle,
            windowState: windowState,
            themeContext: themeContext,
            folderLayoutAnimation: folderLayoutAnimation,
            onUngroup: onUngroup,
            onDelete: onDelete
        )
    }

    func targetCollapsedProjectionIDs(
        using projection: SidebarFolderViewProjection
    ) -> [UUID] {
        guard !folder.isOpen else { return [] }
        return SidebarFolderDisplayProjection.targetCollapsedProjectionIDs(
            shortcutPins: shortcutPinsInFolder,
            projectedChildIDs: folderProjectionState.projectedChildIDs,
            projection: projection
        )
    }

    var isFolderDropHighlighted: Bool {
        folderDragSnapshot.isContainTargeted(folderID: folder.id)
    }

    var folderPreviewIsOpen: Bool {
        folderDragSnapshot.isFolderPreviewOpen(folderID: folder.id, isOpen: folder.isOpen)
    }

    var resolvedTopLevelPinnedIndex: Int {
        containerIndex
    }

    func folderContentProjection(
        using projection: SidebarFolderViewProjection,
        dragSnapshot: SidebarFolderDragSnapshot
    ) -> SidebarFolderContentProjection {
        SidebarFolderContentProjection(
            baseItems: projection.baseItems,
            folderID: folder.id,
            isFolderOpen: folder.isOpen,
            shortcutPins: shortcutPinsInFolder,
            restoreGaps: shortcutRestoreGaps,
            displayedCollapsedProjectionIDs: displayedCollapsedProjectionIDs,
            projectedChildIDs: folderProjectionState.projectedChildIDs,
            projection: projection,
            dragProjection: SidebarFolderDragDisplayProjection(
                dragSnapshot: dragSnapshot,
                folderID: folder.id,
                baseItems: projection.baseItems
            )
        )
    }

    func folderBodyShouldRender(
        contentProjection: SidebarFolderContentProjection
    ) -> Bool {
        folder.isOpen || contentProjection.hasCollapsedProjectionForLayout
    }

    func folderBodyGeometryIsActive(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> Bool {
        isInteractive && folderBodyShouldRender(contentProjection: contentProjection) && !projection.isLiveFolder
    }

    func folderHasActiveSelection(
        using projection: SidebarFolderViewProjection
    ) -> Bool {
        if projection.isLiveFolder,
           let currentURLString = projection.currentTabURLString,
           projection.liveFolderItems.contains(where: { $0.urlString == currentURLString }) {
            return true
        }

        return elevatedFolderIds.contains(folder.id)
    }

    var body: some View {
        SidebarFolderViewProjectionReader(
            folder: folder,
            space: space,
            shortcutPins: shortcutPins,
            childFolders: childFolders,
            shortcutRestoreGaps: shortcutRestoreGaps,
            inventory: inventory,
            selection: selection,
            browserContext: browserContext,
            currentTab: selection.currentTab(in: windowState)
        ) { projection in
            let dragSnapshot = folderDragSnapshot
            let contentProjection = folderContentProjection(
                using: projection,
                dragSnapshot: dragSnapshot
            )

            folderCompositeContent(
                contentProjection: contentProjection,
                projection: projection
            )
                .transaction { transaction in
                    if dragSnapshot.isCompletingDrop {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
                .onChange(of: targetCollapsedProjectionIDs(using: projection)) { _, _ in
                    syncDisplayedCollapsedProjectionIDs(animated: true, projection: projection)
                    scheduleProjectionStateRefresh(projection: projection)
                }
                .onChange(of: folder.isOpen) { _, _ in
                    syncDisplayedCollapsedProjectionIDs(animated: true, projection: projection)
                    scheduleProjectionStateRefresh(projection: projection)
                    refreshLiveFolderIfNeeded()
                }
                .onChange(of: windowState.currentTabId) { _, _ in
                    syncDisplayedCollapsedProjectionIDs(animated: true, projection: projection)
                    scheduleProjectionStateRefresh(projection: projection)
                }
                .onChange(of: windowState.currentShortcutPinId) { _, _ in
                    syncDisplayedCollapsedProjectionIDs(animated: true, projection: projection)
                    scheduleProjectionStateRefresh(projection: projection)
                }
                .onAppear {
                    syncDisplayedCollapsedProjectionIDs(animated: false, projection: projection)
                    scheduleProjectionStateRefresh(projection: projection)
                    refreshLiveFolderIfNeeded()
                }
        }
    }
}
