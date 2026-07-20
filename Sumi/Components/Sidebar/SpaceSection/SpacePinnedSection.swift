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
    let onSetPinnedContentCollapsed: (Bool) -> Void

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
            spaceID: space.id
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
                onSetPinnedContentCollapsed: onSetPinnedContentCollapsed,
                pinnedItems: pinnedItems,
                dragSnapshot: dragSnapshot
            )
        }
    }
}

/// Exact drag values consumed by the pinned section. The broad observable drag
/// object never enters the section's rendering tree.
struct SpacePinnedDragSnapshot: Equatable {
    let isDragging: Bool
    let isCompletingDrop: Bool
    let activeDragItemID: UUID?
    let isHoveringEmptySection: Bool
    let geometryGeneration: Int

    @MainActor
    init(
        dragState: SidebarDragState,
        geometryGeneration: Int,
        spaceID: UUID
    ) {
        let hoveredSpaceID: UUID?
        if case .spacePinned(let candidateSpaceID, _) = dragState.projectionHoveredSlot {
            hoveredSpaceID = candidateSpaceID
        } else {
            hoveredSpaceID = nil
        }

        isDragging = dragState.isDragging
        isCompletingDrop = dragState.isCompletingDrop
        activeDragItemID = dragState.activeDragItemId
        self.geometryGeneration = geometryGeneration
        isHoveringEmptySection = hoveredSpaceID == spaceID
    }
}

private struct SpacePinnedDragSnapshotReader<Content: View>: View {
    let spaceID: UUID
    @ViewBuilder let content: (SpacePinnedDragSnapshot) -> Content

    @EnvironmentObject private var dragState: SidebarDragState
    @EnvironmentObject private var dragGeometry: SidebarDragGeometryModule

    var body: some View {
        content(
            SpacePinnedDragSnapshot(
                dragState: dragState,
                geometryGeneration: dragGeometry.sidebarGeometryGeneration,
                spaceID: spaceID
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
    let onSetPinnedContentCollapsed: (Bool) -> Void
    let pinnedItems: [SpacePinnedListItem]
    let dragSnapshot: SpacePinnedDragSnapshot

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var hasContent: Bool {
        !pinnedItems.isEmpty
    }

    private var hasPinnedContent: Bool {
        !pinnedItems.isEmpty
    }

    private var isCollapsed: Bool {
        windowState.sidebarSpacePinnedCollapse.isCollapsed(space.id)
    }

    private var structuralItemIDs: [UUID] {
        inventory.pinnedStructuralItemIDs()
    }

    private var stickyOwner: SidebarSpacePinnedStickyProjectionOwner {
        SidebarSpacePinnedStickyProjectionOwner(
            space: space,
            inventory: inventory,
            selection: selection,
            selectionSnapshot: sidebarSelection,
            windowState: windowState
        )
    }

    private var visibleStickyItemIDs: [UUID] {
        stickyOwner.visibleStickyItemIDs
    }

    private var showsEmptyDropPlaceholder: Bool {
        !hasContent && isInteractive && dragSnapshot.isHoveringEmptySection
    }

    private var contentMutationAnimation: Animation? {
        guard isInteractive,
              !reduceMotion,
              !sumiSettings.shouldReduceChromeMotion
        else { return nil }
        let mode = SidebarMotionPolicy.currentMode(
            reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
        )
        // Drop commit settles rows into place with the short Zen-style slide.
        return dragSnapshot.isCompletingDrop
            ? SidebarMotionPolicy.dropSettleAnimation(for: mode)
            : SidebarMotionPolicy.folderLayoutAnimation(for: mode)
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
                pinnedContent
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
        .animation(contentMutationAnimation, value: visibleStickyItemIDs)
        .animation(contentMutationAnimation, value: isCollapsed)
        .sidebarSectionGeometry(
            for: .spacePinned,
            spaceId: space.id,
            generation: dragSnapshot.geometryGeneration,
            isEnabled: isInteractive
        )
        .onAppear {
            stickyOwner.reconcileOnAppear()
            if !hasPinnedContent, isCollapsed {
                onSetPinnedContentCollapsed(false)
            }
        }
        .onChange(of: sidebarSelection) { _, _ in
            stickyOwner.handleSelectionChange()
        }
        .onChange(of: dragSnapshot.isCompletingDrop) { _, isCompletingDrop in
            if isCompletingDrop,
               isCollapsed,
               dragSnapshot.isHoveringEmptySection {
                onSetPinnedContentCollapsed(false)
            }
        }
        .onChange(of: structuralItemIDs) { oldIDs, newIDs in
            stickyOwner.handleMembershipChange()
            guard isCollapsed else { return }
            if newIDs.isEmpty || !Set(newIDs).subtracting(oldIDs).isEmpty {
                onSetPinnedContentCollapsed(false)
            }
        }
    }

    @ViewBuilder
    private var pinnedContent: some View {
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
            isCollapsed: isCollapsed,
            pinnedItems: pinnedItems,
            stickyItemIDs: visibleStickyItemIDs,
            dragSnapshot: dragSnapshot,
            contentMutationAnimation: contentMutationAnimation,
            actionOwner: actionOwner
        )
    }

    private var emptyRevealStrip: some View {
        // Rests at zero height (Zen: an empty pinned section adds no gap under
        // the title); grows into a drop target only while a drag hovers it.
        Color.clear
            .frame(
                height: showsEmptyDropPlaceholder ? SidebarRowLayout.rowHeight : 0
            )
            .frame(maxWidth: .infinity)
    }
}
