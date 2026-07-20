//
//  PinnedGridLayoutModel.swift
//  Sumi
//

import SwiftUI

/// Aggregates the essentials-grid layout/drop-projection derivation that
/// `PinnedGrid` needs to render a frame: which items are visible, how they're
/// projected during a drag, the resolved display rows, and the drop-target
/// geometry. Orchestrates `SidebarEssentialsProjectionPolicy` and
/// `SidebarEssentialsGridProjection` — the pure math lives there; this type's
/// job is bundling their outputs into the single snapshot `PinnedGrid.body`
/// consumes, so that orchestration can be tested independently of SwiftUI.
@MainActor
struct PinnedGridLayoutModel {
    private static let collapsedRevealHeight: CGFloat = 6

    let width: CGFloat
    let items: [SidebarEssentialVisualItem]
    let dragState: SidebarDragState
    let geometrySpaceId: UUID
    let effectiveProfileId: UUID?
    let shouldAnimateDropLayout: Bool
    let shouldAnimateContentLayout: Bool
    let reportsDetailedGeometry: Bool

    private let gridProjection: SidebarEssentialsGridProjection
    let projectedLayout: SidebarEssentialsProjectedLayout

    init(
        width: CGFloat,
        items: [SidebarEssentialVisualItem],
        dragState: SidebarDragState,
        geometrySpaceId: UUID,
        effectiveProfileId: UUID?,
        animateLayout: Bool,
        reportsGeometry: Bool,
        isActiveWindow: Bool,
        isTransitioningProfile: Bool,
        shouldReduceMotion: Bool
    ) {
        self.width = width
        self.items = items
        self.dragState = dragState
        self.geometrySpaceId = geometrySpaceId
        self.effectiveProfileId = effectiveProfileId

        gridProjection = SidebarEssentialsGridProjection(width: width)
        projectedLayout = SidebarEssentialsProjectionPolicy.make(
            items: items,
            width: width,
            dragState: dragState
        )
        reportsDetailedGeometry = reportsGeometry
            && dragState.shouldCollectDetailedGeometry(
                spaceId: geometrySpaceId,
                profileId: effectiveProfileId
            )
        let animationsAllowed = animateLayout && isActiveWindow && !isTransitioningProfile && !shouldReduceMotion
        shouldAnimateDropLayout = animationsAllowed && dragState.shouldAnimateDropLayout
        shouldAnimateContentLayout = animationsAllowed
    }

    var isHoveringThisEssentials: Bool {
        guard dragState.isDropProjectionActive,
              case .essentials = dragState.projectionHoveredSlot else {
            return false
        }
        return true
    }

    var showsRevealGap: Bool {
        items.isEmpty && isHoveringThisEssentials && projectedLayout.canAcceptDrop
    }

    var revealTileSize: CGSize {
        projectedLayout.rows.first?.tileSize ?? projectedLayout.tileSize
    }

    var revealHeight: CGFloat {
        showsRevealGap ? revealTileSize.height : Self.collapsedRevealHeight
    }

    var visibleRowCount: Int {
        max(projectedLayout.visibleRowCount, items.isEmpty ? 0 : 1)
    }

    var maxDropRowCount: Int {
        items.isEmpty
            ? 1
            : SidebarEssentialsProjectionPolicy.neededRowCountAfterDrop(
                itemIDs: items.map(\.id),
                visibleItemCount: projectedLayout.visibleItemCount,
                layoutItemCount: projectedLayout.projectedItemCount,
                columnCount: projectedLayout.columnCount,
                canAcceptDrop: projectedLayout.canAcceptDrop,
                dragState: dragState
            )
    }

    var dropFrame: CGRect {
        items.isEmpty
            ? CGRect(x: 0, y: 0, width: width, height: revealHeight)
            : gridProjection.resolvedDropFrame(
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount,
                tileSize: projectedLayout.tileSize,
                visibleHeight: gridProjection.projectedContentHeight(for: projectedLayout)
            )
    }

    var previewState: SidebarEssentialsPreviewState? {
        dragState.essentialsPreviewState(for: geometrySpaceId).flatMap {
            gridProjection.resolvedPreviewState(
                $0,
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount
            )
        }
    }

    var displayRows: [SidebarEssentialsDisplayRow] {
        gridProjection.resolvedDisplayRows(
            for: projectedLayout,
            previewState: previewState,
            maxDropRowCount: maxDropRowCount
        )
    }

    var displayLayoutSignature: [String] {
        displayRows.flatMap(\.layoutSignature)
    }

    var dropSlotFrames: [SidebarEssentialsDropSlotMetrics] {
        gridProjection.resolvedDropSlotFrames(
            for: projectedLayout,
            revealTileSize: revealTileSize,
            maxDropRowCount: maxDropRowCount
        )
    }

    var firstSyntheticRowSlot: Int {
        max(visibleRowCount, 1) * max(projectedLayout.capacityColumnCount, 1)
    }
}
