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
    @Binding var shortcutRestoreSession: SpaceShortcutRestoreInteractionSession
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

    private var shortcutPinsInFolder: [ShortcutPin] {
        inventory.folderPinsByFolderID[folder.id] ?? []
    }

    private var folderProjectionState: SidebarFolderProjectionState {
        windowState.sidebarFolderProjections.projection(for: folder.id)
    }

    private var folderLayoutAnimation: Animation? {
        dragSnapshot.allowsLayoutAnimation(isInteractive: isInteractive)
            ? SidebarMotionPolicy.folderLayoutAnimation(
                for: SidebarMotionPolicy.currentMode(
                    reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
                )
            )
            : nil
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
            shortcutPins: shortcutPinsInFolder,
            projectedChildIDs: folderProjectionState.projectedChildIDs,
            projection: projection
        )
    }

    private var contentProjection: SidebarFolderContentProjection {
        SidebarFolderContentProjection(
            baseItems: projection.baseItems,
            folderID: folder.id,
            isFolderOpen: folder.isOpen,
            shortcutPins: shortcutPinsInFolder,
            restoreGaps: shortcutRestoreSession.gaps,
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
                scheduleProjectionStateRefresh()
            }
            .onChange(of: folder.isOpen) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
                refreshLiveFolderIfNeeded()
            }
            .onChange(of: windowState.currentTabId) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
            }
            .onChange(of: windowState.currentShortcutPinId) { _, _ in
                syncDisplayedCollapsedProjectionIDs(animated: true)
                scheduleProjectionStateRefresh()
            }
            .onAppear {
                syncDisplayedCollapsedProjectionIDs(animated: false)
                scheduleProjectionStateRefresh()
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
                onActivateShortcutPin: mutationActions.activateShortcutPin
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
            shortcutRestoreSession: $shortcutRestoreSession,
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

    private func scheduleProjectionStateRefresh() {
        let projectedIDs = SidebarFolderDisplayProjection.targetCollapsedProjectionPins(
            shortcutPins: shortcutPinsInFolder,
            projectedChildIDs: folderProjectionState.projectedChildIDs,
            projection: projection
        ).map(\.id)
        let hasActiveProjection = folderHasActiveSelection || !projectedIDs.isEmpty
        windowState.sidebarFolderProjections.scheduleUpdate(
            for: folder.id,
            projectedChildIDs: projectedIDs,
            hasActiveProjection: hasActiveProjection
        )
    }

    private func syncDisplayedCollapsedProjectionIDs(animated: Bool) {
        let targetIDs = targetCollapsedProjectionIDs
        guard displayedCollapsedProjectionIDs != targetIDs else { return }

        let update = {
            displayedCollapsedProjectionIDs = targetIDs
        }

        if animated && dragSnapshot.allowsLayoutAnimation(isInteractive: isInteractive) {
            withAnimation(folderLayoutAnimation, update)
        } else {
            update()
        }
    }
}
