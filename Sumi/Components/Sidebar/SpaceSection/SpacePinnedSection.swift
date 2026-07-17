//
//  SpacePinnedSection.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// State/composition root for one space's saved content.
struct SpacePinnedSectionView: View {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    @Binding var shortcutRestoreSession: SpaceShortcutRestoreInteractionSession

    @Environment(BrowserWindowState.self) private var windowState

    private var pinnedItems: [SpacePinnedListItem] {
        guard !windowState.isIncognito else { return [] }
        return inventory.topLevelItems.map { item in
            switch item {
            case .folder(let id): return .folder(id)
            case .shortcut(let id): return .shortcut(id)
            case .splitGroup(let id): return .splitGroup(id)
            }
        }
    }

    var body: some View {
        SpacePinnedDragSnapshotReader(
            spaceID: space.id,
            pinnedItems: pinnedItems
        ) { dragSnapshot in
            SpacePinnedSectionContentView(
                space: space,
                inventory: inventory,
                selection: selection,
                pinProjection: pinProjection,
                pinCommands: pinCommands,
                pinExecution: pinExecution,
                folderCommands: folderCommands,
                spaceLifecycle: spaceLifecycle,
                browserContext: browserContext,
                isInteractive: isInteractive,
                pinnedItems: pinnedItems,
                dragSnapshot: dragSnapshot,
                shortcutRestoreSession: $shortcutRestoreSession
            )
        }
    }
}

/// Exact drag values consumed by the pinned section. The broad observable drag
/// object never enters the section's rendering tree.
struct SpacePinnedDragSnapshot {
    let isDragging: Bool
    let isCompletingDrop: Bool
    let activeDragItemID: UUID?
    let isHoveringEmptySection: Bool
    let geometryGeneration: Int
    let shouldAnimateDropLayout: Bool
    let projection: SpacePinnedListProjection.DragProjectionSnapshot

    @MainActor
    init(
        dragState: SidebarDragState,
        spaceID: UUID,
        pinnedItems: [SpacePinnedListItem]
    ) {
        let hoveredSpaceID: UUID?
        let hoveredSlot: Int?
        if case .spacePinned(let candidateSpaceID, let slot) = dragState.projectionHoveredSlot {
            hoveredSpaceID = candidateSpaceID
            hoveredSlot = slot
        } else {
            hoveredSpaceID = nil
            hoveredSlot = nil
        }

        let targetContainsDraggedItem = dragState.projectionDragItemId.map { dragItemID in
            pinnedItems.contains { $0.id == dragItemID }
        } ?? false

        isDragging = dragState.isDragging
        isCompletingDrop = dragState.isCompletingDrop
        activeDragItemID = dragState.activeDragItemId
        geometryGeneration = dragState.sidebarGeometryGeneration
        shouldAnimateDropLayout = dragState.shouldAnimateDropLayout
        if case .spacePinned(let hoveredSpaceID, _) = dragState.hoveredSlot {
            isHoveringEmptySection = hoveredSpaceID == spaceID
        } else {
            isHoveringEmptySection = false
        }
        projection = .init(
            isDropProjectionActive: dragState.isDropProjectionActive,
            sourceContainer: dragState.projectionDragScope?.sourceContainer,
            dragItemId: dragState.projectionDragItemId,
            hoveredSpaceId: hoveredSpaceID,
            hoveredSlot: hoveredSlot,
            folderDropIntent: dragState.projectionFolderDropIntent,
            hidesCommittedCrossContainerPlaceholder: dragState.shouldHideCommittedCrossContainerPlaceholder(
                into: .spacePinned(spaceID),
                targetAlreadyContainsDraggedItem: targetContainsDraggedItem
            )
        )
    }
}

private struct SpacePinnedDragSnapshotReader<Content: View>: View {
    let spaceID: UUID
    let pinnedItems: [SpacePinnedListItem]
    @ViewBuilder let content: (SpacePinnedDragSnapshot) -> Content

    @EnvironmentObject private var dragState: SidebarDragState

    var body: some View {
        content(
            SpacePinnedDragSnapshot(
                dragState: dragState,
                spaceID: spaceID,
                pinnedItems: pinnedItems
            )
        )
    }
}

/// Chooses the list/empty presentation and owns section-scoped behavior.
private struct SpacePinnedSectionContentView: View {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let pinnedItems: [SpacePinnedListItem]
    let dragSnapshot: SpacePinnedDragSnapshot
    @Binding var shortcutRestoreSession: SpaceShortcutRestoreInteractionSession

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasContent: Bool {
        !pinnedItems.isEmpty
            || shortcutRestoreSession.gaps.contains { $0.container == .spacePinned(space.id) }
    }

    private var showsEmptyDropPlaceholder: Bool {
        !hasContent && isInteractive && dragSnapshot.isHoveringEmptySection
    }

    private var contentMutationAnimation: Animation? {
        guard isInteractive,
              !reduceMotion,
              !sumiSettings.shouldReduceChromeMotion,
              !dragSnapshot.isCompletingDrop
        else { return nil }
        return SidebarMotionPolicy.folderLayoutAnimation(
            for: SidebarMotionPolicy.currentMode(
                reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
            )
        )
    }

    private var actionOwner: SpacePinnedActionOwner {
        SpacePinnedActionOwner(
            space: space,
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
            contentMutationAnimation: contentMutationAnimation
        )
    }

    var body: some View {
        Group {
            if hasContent {
                SpacePinnedListView(
                    space: space,
                    inventory: inventory,
                    selection: selection,
                    pinProjection: pinProjection,
                    pinCommands: pinCommands,
                    pinExecution: pinExecution,
                    folderCommands: folderCommands,
                    spaceLifecycle: spaceLifecycle,
                    browserContext: browserContext,
                    isInteractive: isInteractive,
                    pinnedItems: pinnedItems,
                    dragSnapshot: dragSnapshot,
                    contentMutationAnimation: contentMutationAnimation,
                    actionOwner: actionOwner,
                    shortcutRestoreSession: $shortcutRestoreSession
                )
                .transition(
                    isInteractive
                        ? .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.95, anchor: .top))
                                .animation(.easeInOut(duration: 0.3)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.95, anchor: .top))
                                .animation(.easeInOut(duration: 0.2))
                        )
                        : .identity
                )
            } else {
                emptyRevealStrip
            }
        }
        .animation(isInteractive ? .easeInOut(duration: 0.25) : nil, value: hasContent)
        .animation(isInteractive ? .easeInOut(duration: 0.18) : nil, value: showsEmptyDropPlaceholder)
        .animation(contentMutationAnimation, value: pinnedItems)
        .transaction { transaction in
            if dragSnapshot.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .sidebarSectionGeometry(
            for: .spacePinned,
            spaceId: space.id,
            generation: dragSnapshot.geometryGeneration,
            isEnabled: isInteractive
        )
    }

    private var emptyRevealStrip: some View {
        Color.clear
            .frame(
                height: showsEmptyDropPlaceholder ? SidebarRowLayout.rowHeight : 6
            )
            .frame(maxWidth: .infinity)
    }
}
