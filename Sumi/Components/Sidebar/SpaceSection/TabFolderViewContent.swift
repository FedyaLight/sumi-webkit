//
//  TabFolderViewContent.swift
//  Sumi
//

import SumiDomain
import SwiftUI

extension TabFolderView {
    func refreshLiveFolderIfNeeded() {
        guard folder.isOpen else { return }
        browserContext.liveFolderManager.refreshIfStale(folderId: folder.id)
    }

    func folderCompositeContent(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        VStack(spacing: 0) {
            TabFolderHeaderView(
                folder: folder,
                space: space,
                browserContext: browserContext,
                inventory: inventory,
                selection: selection,
                parentFolderId: parentFolderId,
                topLevelIndex: resolvedTopLevelPinnedIndex,
                contentProjection: contentProjection,
                projection: projection,
                isInteractive: isInteractive,
                isDropHighlighted: isFolderDropHighlighted,
                folderPreviewIsOpen: folderPreviewIsOpen,
                hasActiveSelection: folderHasActiveSelection(using: projection),
                hasActiveProjection: folderProjectionState.hasActiveProjection,
                geometryGeneration: folderDragSnapshot.geometryGeneration,
                contextMenuEntries: {
                    contextMenuActionOwner.folderHeaderContextMenuEntries()
                },
                onToggle: {
                    mutationActions.toggleFolderOpenState(folder.id)
                },
                onActivateShortcutPin: activateShortcutPin
            )
            folderBodyContainer(
                contentProjection: contentProjection,
                projection: projection
            )
        }
        .background(alignment: .bottom) {
            folderAfterDropTarget(childCount: contentProjection.childCount)
        }
    }

    @ViewBuilder
    func folderBodyContainer(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        folderBodyAnimatedContent(
            contentProjection: contentProjection,
            projection: projection
        )
            .sidebarFolderDropGeometry(
                folderId: folder.id,
                spaceId: space.id,
                parentFolderId: parentFolderId,
                topLevelIndex: resolvedTopLevelPinnedIndex,
                childCount: contentProjection.childCount,
                isOpen: folder.isOpen,
                region: .body,
                generation: folderDragSnapshot.geometryGeneration,
                isActive: folderBodyGeometryIsActive(
                    contentProjection: contentProjection,
                    projection: projection
                )
            )
    }

    @ViewBuilder
    func folderBodyAnimatedContent(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        if folderBodyShouldRender(contentProjection: contentProjection) {
            folderBodyVisibleContent(contentProjection: contentProjection, projection: projection)
                .transition(.sidebarRowContentOpacity)
                .animation(folderLayoutAnimation, value: folder.isOpen)
                .animation(folderLayoutAnimation, value: contentProjection.bodyItems)
                .animation(folderLayoutAnimation, value: displayedCollapsedProjectionIDs)
                .animation(folderLayoutAnimation, value: contentProjection.targetCollapsedProjectionIDs)
        } else {
            Color.clear
                .frame(height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    func folderBodyVisibleContent(
        contentProjection: SidebarFolderContentProjection,
        projection: SidebarFolderViewProjection
    ) -> some View {
        TabFolderBodyListView(
            folder: folder,
            browserContext: browserContext,
            space: space,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            spaceLifecycle: spaceLifecycle,
            shortcutPins: shortcutPinsInFolder,
            childFolders: childFolders,
            childFoldersByParentId: childFoldersByParentId,
            folderPinsByFolderId: folderPinsByFolderId,
            shortcutRestoreGaps: $shortcutRestoreGaps,
            shortcutRestoreAppearingGapIds: $shortcutRestoreAppearingGapIds,
            elevatedFolderIds: elevatedFolderIds,
            renderMode: renderMode,
            nestingDepth: nestingDepth,
            contentProjection: contentProjection,
            projection: projection,
            reportsGeometry: true,
            reportsFolderChildGeometry: folder.isOpen,
            folderLayoutAnimation: folderLayoutAnimation,
            contextMenuActionOwner: contextMenuActionOwner,
            mutationActions: mutationActions,
            onPrepareShortcutRestoreGap: onPrepareShortcutRestoreGap,
            onPerformShortcutRestoreWithPreparedGap: onPerformShortcutRestoreWithPreparedGap,
            onActivateShortcutPin: activateShortcutPin
        )
        .allowsHitTesting(folder.isOpen || !contentProjection.visibleCollapsedProjectionIDs.isEmpty)
        .animation(folderLayoutAnimation, value: folder.isOpen)
        .animation(folderLayoutAnimation, value: contentProjection.bodyItems)
        .animation(folderLayoutAnimation, value: displayedCollapsedProjectionIDs)
        .animation(folderLayoutAnimation, value: contentProjection.targetCollapsedProjectionIDs)
    }

    @ViewBuilder
    func folderAfterDropTarget(childCount: Int) -> some View {
        let dragSnapshot = folderDragSnapshot
        let height = dragSnapshot.afterDropTargetHeight(rowHeight: SidebarRowLayout.rowHeight)
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .offset(y: height / 2)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .sidebarFolderDropGeometry(
                folderId: folder.id,
                spaceId: space.id,
                parentFolderId: parentFolderId,
                topLevelIndex: resolvedTopLevelPinnedIndex,
                childCount: childCount,
                isOpen: folder.isOpen,
                region: .after,
                generation: dragSnapshot.geometryGeneration,
                isActive: isInteractive && height > 0
            )
            .allowsHitTesting(false)
    }

    func scheduleProjectionStateRefresh(
        projection: SidebarFolderViewProjection
    ) {
        let projectedIDs = SidebarFolderDisplayProjection.targetCollapsedProjectionPins(
            shortcutPins: shortcutPinsInFolder,
            projectedChildIDs: folderProjectionState.projectedChildIDs,
            projection: projection
        ).map(\.id)
        let newHasActiveProjection = folderHasActiveSelection(using: projection) || !projectedIDs.isEmpty
        windowState.sidebarFolderProjections.scheduleUpdate(
            for: folder.id,
            projectedChildIDs: projectedIDs,
            hasActiveProjection: newHasActiveProjection
        )
    }

    func syncDisplayedCollapsedProjectionIDs(
        animated: Bool,
        projection: SidebarFolderViewProjection
    ) {
        let targetIDs = targetCollapsedProjectionIDs(using: projection)
        guard displayedCollapsedProjectionIDs != targetIDs else { return }

        let update = {
            displayedCollapsedProjectionIDs = targetIDs
        }

        if animated && folderDragSnapshot.allowsLayoutAnimation(isInteractive: isInteractive) {
            withAnimation(folderLayoutAnimation, update)
        } else {
            update()
        }
    }

    func activateShortcutPin(_ pin: ShortcutPin) {
        mutationActions.activateShortcutPin(pin)
    }

}
