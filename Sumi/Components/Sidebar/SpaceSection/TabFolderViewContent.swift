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
    private static let folderBodyVerticalPadding: CGFloat = 4

    let folder: TabFolder
    let presentation: SidebarFolderPresentationCell
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
            presentation: presentation,
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

    private var disclosureAnimation: Animation? {
        guard isInteractive else { return nil }
        return SidebarMotionPolicy.disclosureAnimation(
            for: SidebarMotionPolicy.currentMode(
                reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
            )
        )
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
        guard !presentation.isExpanded else { return [] }
        return SidebarFolderDisplayProjection.targetCollapsedProjectionIDs(
            stickyItemIDs: SidebarFolderDisplayProjection.disclosureTargetStickyItemIDs(
                currentStickyItemIDs: folderProjectionState.stickyItemIDs,
                selectedDescendantItemID: projection.selectedCollapsedProjectionItemID
            ),
            orderedDescendantItemIDs: orderedDescendantItemIDs,
            projection: projection
        )
    }

    private var contentProjection: SidebarFolderContentProjection {
        SidebarFolderContentProjection(
            baseItems: projection.baseItems,
            isFolderOpen: presentation.isExpanded,
            displayedCollapsedProjectionIDs: displayedCollapsedProjectionIDs,
            stickyItemIDs: folderProjectionState.stickyItemIDs,
            orderedDescendantItemIDs: orderedDescendantItemIDs,
            projection: projection
        )
    }

    private var folderBodyShouldRender: Bool {
        presentation.isExpanded || contentProjection.hasCollapsedProjectionForLayout
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
            .onChange(of: presentation.isExpanded) { _, isOpen in
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
                presentation: presentation,
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
                    isOpen: presentation.isExpanded
                ),
                hasActiveSelection: folderHasActiveSelection,
                hasActiveProjection: folderProjectionState.hasActiveProjection,
                geometryGeneration: dragSnapshot.geometryGeneration,
                isDragging: dragSnapshot.isDragging,
                contextMenuEntries: { contextMenuActionOwner.folderHeaderContextMenuEntries() },
                onToggle: { mutationActions.toggleFolderOpenState(folder.id) },
                onActivateShortcutPin: mutationActions.activateShortcutPin,
                onResetProjection: !presentation.isExpanded
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
        SidebarDisclosureHost(
            target: SidebarDisclosureTarget(
                isRevealed: presentation.isExpanded,
                items: contentProjection.bodyItems,
                topPadding: folderBodyShouldRender
                    ? Self.folderBodyVerticalPadding
                    : 0,
                bottomPadding: folderBodyShouldRender
                    ? Self.folderBodyVerticalPadding
                    : 0
            ),
            disclosureAnimation: disclosureAnimation,
            layoutAnimation: folderLayoutAnimation
        ) { disclosurePresentation, reportsGeometry in
            folderBodyVisibleContent(
                disclosurePresentation: disclosurePresentation,
                reportsGeometry: reportsGeometry
            )
        }
            .sidebarFolderDropGeometry(
                folderId: folder.id,
                spaceId: space.id,
                parentFolderId: parentFolderId,
                topLevelIndex: containerIndex,
                childCount: contentProjection.childCount,
                isOpen: presentation.isExpanded,
                region: .body,
                generation: dragSnapshot.geometryGeneration,
                isActive: folderBodyGeometryIsActive
            )
    }

    private func folderBodyVisibleContent(
        disclosurePresentation: SidebarDisclosurePresentation<SidebarFolderListItem>,
        reportsGeometry: Bool
    ) -> some View {
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
            disclosurePresentation: disclosurePresentation,
            projection: projection,
            reportsGeometry: reportsGeometry,
            reportsFolderChildGeometry: presentation.isExpanded,
            contextMenuActionOwner: contextMenuActionOwner,
            mutationActions: mutationActions,
            dragSnapshot: dragSnapshot
        )
        .allowsHitTesting(
            presentation.isExpanded || !contentProjection.visibleCollapsedProjectionIDs.isEmpty
        )
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
                isOpen: presentation.isExpanded,
                region: .after,
                generation: dragSnapshot.geometryGeneration,
                isActive: isInteractive && height > 0
            )
            .allowsHitTesting(false)
    }

    private func refreshLiveFolderIfNeeded() {
        guard presentation.isExpanded else { return }
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
