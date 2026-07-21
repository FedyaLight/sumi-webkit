//
//  TabFolderViewContent.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Owns one folder's concrete rendering and projection reactions.
///
/// `TabFolderView` keeps the recursive state boundary, while this view keeps
/// header/body rendering out of that recursive composition root.
struct TabFolderContentView: View {
    let folder: TabFolder
    let browserContext: SidebarBrowserContext
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    @Binding var displayedCollapsedProjectionIDs: [UUID]
    let elevatedFolderIds: Set<UUID>
    let isInteractive: Bool
    let parentFolderId: UUID?
    let containerIndex: Int
    let nestingDepth: Int
    let projection: SidebarFolderViewProjection
    let dragSnapshot: SidebarFolderDragSnapshot

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var folderProjectionState: SidebarFolderProjectionState {
        // Pending-aware read: collapse/selection handlers schedule sticky
        // writes in the same tick the row re-renders, and the collapsed
        // projection must animate with them, not one flush later.
        windowState.sidebarFolderProjections.pendingOrCurrentProjection(for: folder.id)
    }

    private var orderedDescendantItemIDs: [UUID] {
        inventory.orderedDescendantItemIDs(for: folder.id)
    }

    private var stickyOwner: SidebarFolderStickyProjectionOwner {
        SidebarFolderStickyProjectionOwner(
            folder: folder,
            inventory: inventory,
            selection: selection,
            selectionSnapshot: sidebarSelection,
            windowState: windowState
        )
    }

    private var folderLayoutAnimation: Animation? {
        guard isInteractive else { return nil }
        let mode = SidebarMotionPolicy.currentMode(
            reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
        )
        // Drop commit settles rows into place with the short Zen-style slide.
        return dragSnapshot.isCompletingDrop
            ? SidebarMotionPolicy.dropSettleAnimation(for: mode)
            : SidebarMotionPolicy.folderLayoutAnimation(for: mode)
    }

    private var mutationActions: TabFolderMutationActions {
        TabFolderMutationActions(
            browserContext: browserContext,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            windowState: windowState,
            windowRegistry: windowRegistry,
            themeContext: themeContext,
            space: space,
            folderLayoutAnimation: folderLayoutAnimation
        )
    }

    private var contextMenuActionOwner: TabFolderContextMenuActionOwner {
        TabFolderContextMenuActionOwner(
            folder: folder,
            space: space,
            childFoldersByParentId: inventory.childFoldersByParentID,
            folderPinsByFolderId: inventory.folderPinsByFolderID,
            browserContext: browserContext,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            spaceLifecycle: spaceLifecycle,
            windowState: windowState,
            themeContext: themeContext,
            folderLayoutAnimation: folderLayoutAnimation,
            mutationActions: mutationActions
        )
    }

    private var targetCollapsedProjectionIDs: [UUID] {
        guard !folder.isOpen else { return [] }
        return SidebarFolderDisplayProjection.targetCollapsedProjectionIDs(
            stickyItemIDs: folderProjectionState.stickyItemIDs,
            orderedDescendantItemIDs: orderedDescendantItemIDs,
            projection: projection
        )
    }

    private var contentProjection: SidebarFolderContentProjection {
        SidebarFolderContentProjection(
            baseItems: projection.baseItems,
            isFolderOpen: folder.isOpen,
            displayedCollapsedProjectionIDs: displayedCollapsedProjectionIDs,
            stickyItemIDs: folderProjectionState.stickyItemIDs,
            orderedDescendantItemIDs: orderedDescendantItemIDs,
            projection: projection
        )
    }

    private var folderBodyShouldRender: Bool {
        folder.isOpen || contentProjection.hasCollapsedProjectionForLayout
    }

    private var folderBodyGeometryIsActive: Bool {
        isInteractive && folderBodyShouldRender && !projection.isLiveFolder
    }

    private var folderHasActiveSelection: Bool {
        if projection.isLiveFolder,
           let currentURLString = projection.currentTabURLString,
           projection.liveFolderItems.contains(where: { $0.urlString == currentURLString }) {
            return true
        }

        return elevatedFolderIds.contains(folder.id)
    }

    var body: some View {
        folderCompositeContent
            .onChange(of: targetCollapsedProjectionIDs) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                stickyOwner.prunePublish()
            }
            .onChange(of: folder.isOpen) { _, isOpen in
                if isOpen {
                    stickyOwner.handleExpand()
                } else {
                    stickyOwner.handleCollapse()
                }
                syncDisplayedCollapsedProjectionIDs(animated: true)
                refreshLiveFolderIfNeeded()
            }
            .onChange(of: sidebarSelection) { _, _ in
                stickyOwner.handleSelectionChange()
                syncDisplayedCollapsedProjectionIDs(animated: true)
            }
            .onChange(of: orderedDescendantItemIDs) { _, _ in
                stickyOwner.handleMembershipChange()
                syncDisplayedCollapsedProjectionIDs(animated: true)
            }
            .onAppear {
                stickyOwner.reconcileOnAppear()
                syncDisplayedCollapsedProjectionIDs(animated: false)
                refreshLiveFolderIfNeeded()
            }
    }

    private var folderCompositeContent: some View {
        VStack(spacing: 0) {
            TabFolderHeaderView(
                folder: folder,
                space: space,
                browserContext: browserContext,
                inventory: inventory,
                selection: selection,
                pinProjection: pinProjection,
                parentFolderId: parentFolderId,
                topLevelIndex: containerIndex,
                contentProjection: contentProjection,
                projection: projection,
                isInteractive: isInteractive,
                isDropHighlighted: dragSnapshot.isContainTargeted(folderID: folder.id),
                folderPreviewIsOpen: dragSnapshot.isFolderPreviewOpen(
                    folderID: folder.id,
                    isOpen: folder.isOpen
                ),
                hasActiveSelection: folderHasActiveSelection,
                hasActiveProjection: folderProjectionState.hasActiveProjection,
                geometryGeneration: dragSnapshot.geometryGeneration,
                isDragging: dragSnapshot.isDragging,
                contextMenuEntries: { contextMenuActionOwner.folderHeaderContextMenuEntries() },
                onToggle: { mutationActions.toggleFolderOpenState(folder.id) },
                onActivateShortcutPin: mutationActions.activateShortcutPin,
                onResetProjection: !folder.isOpen
                    && !contentProjection.visibleCollapsedProjectionIDs.isEmpty
                    ? { mutationActions.resetCollapsedProjection(folder, inventory: inventory) }
                    : nil
            )
            folderBodyContainer
        }
        .background(alignment: .bottom) {
            folderAfterDropTarget
        }
    }

    private var folderBodyContainer: some View {
        folderBodyAnimatedContent
            .sidebarFolderDropGeometry(
                folderId: folder.id,
                spaceId: space.id,
                parentFolderId: parentFolderId,
                topLevelIndex: containerIndex,
                childCount: contentProjection.childCount,
                isOpen: folder.isOpen,
                region: .body,
                generation: dragSnapshot.geometryGeneration,
                isActive: folderBodyGeometryIsActive
            )
    }

    @ViewBuilder
    private var folderBodyAnimatedContent: some View {
        if folderBodyShouldRender {
            folderBodyVisibleContent
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

    private var folderBodyVisibleContent: some View {
        TabFolderBodyListView(
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
            elevatedFolderIds: elevatedFolderIds,
            isInteractive: isInteractive,
            nestingDepth: nestingDepth,
            contentProjection: contentProjection,
            projection: projection,
            reportsGeometry: true,
            reportsFolderChildGeometry: folder.isOpen,
            folderLayoutAnimation: folderLayoutAnimation,
            contextMenuActionOwner: contextMenuActionOwner,
            mutationActions: mutationActions,
            dragSnapshot: dragSnapshot
        )
        .allowsHitTesting(folder.isOpen || !contentProjection.visibleCollapsedProjectionIDs.isEmpty)
        .animation(folderLayoutAnimation, value: folder.isOpen)
        .animation(folderLayoutAnimation, value: contentProjection.bodyItems)
        .animation(folderLayoutAnimation, value: displayedCollapsedProjectionIDs)
        .animation(folderLayoutAnimation, value: contentProjection.targetCollapsedProjectionIDs)
    }

    private var folderAfterDropTarget: some View {
        let height = dragSnapshot.afterDropTargetHeight(rowHeight: SidebarRowLayout.rowHeight)
        return Color.clear
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
                topLevelIndex: containerIndex,
                childCount: contentProjection.childCount,
                isOpen: folder.isOpen,
                region: .after,
                generation: dragSnapshot.geometryGeneration,
                isActive: isInteractive && height > 0
            )
            .allowsHitTesting(false)
    }

    private func refreshLiveFolderIfNeeded() {
        guard folder.isOpen else { return }
        browserContext.liveFolderManager.refreshIfStale(folderId: folder.id)
    }

    private func syncDisplayedCollapsedProjectionIDs(animated: Bool) {
        let targetIDs = targetCollapsedProjectionIDs
        guard displayedCollapsedProjectionIDs != targetIDs else { return }

        let update = {
            displayedCollapsedProjectionIDs = targetIDs
        }

        if animated, let folderLayoutAnimation {
            withAnimation(folderLayoutAnimation, update)
        } else {
            update()
        }
    }
}
