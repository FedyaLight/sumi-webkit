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
    /// How the zone presents itself while it holds no Essentials.
    enum EmptyPresentation: Equatable {
        /// Invisible strip: the hint was dismissed and no drag is hovering.
        case collapsed
        /// The dashed placeholder — either the un-dismissed hint, or the
        /// drag-hover reveal that replaces it once dismissed.
        case placeholder
    }

    let width: CGFloat
    let items: [SidebarEssentialVisualItem]
    let dragPresentation: SidebarEssentialsDragPresentationFrame
    let dragGeometry: SidebarDragGeometryModule
    let geometrySpaceId: UUID
    let effectiveProfileId: UUID?
    let showsHint: Bool
    let shouldAnimateDropLayout: Bool
    let shouldAnimateContentLayout: Bool
    let reportsDetailedGeometry: Bool

    private let gridProjection: SidebarEssentialsGridProjection
    let projectedLayout: SidebarEssentialsProjectedLayout

    init(
        width: CGFloat,
        items: [SidebarEssentialVisualItem],
        dragPresentation: SidebarEssentialsDragPresentationFrame,
        dragGeometry: SidebarDragGeometryModule,
        geometrySpaceId: UUID,
        effectiveProfileId: UUID?,
        showsHint: Bool,
        animateLayout: Bool,
        reportsGeometry: Bool,
        isActiveWindow: Bool,
        isTransitioningProfile: Bool,
        shouldReduceMotion: Bool
    ) {
        self.width = width
        self.items = items
        self.dragPresentation = dragPresentation
        self.dragGeometry = dragGeometry
        self.geometrySpaceId = geometrySpaceId
        self.effectiveProfileId = effectiveProfileId
        self.showsHint = showsHint

        gridProjection = SidebarEssentialsGridProjection(width: width)
        projectedLayout = SidebarEssentialsProjectionPolicy.make(
            items: items,
            width: width,
            dragPresentation: dragPresentation
        )
        reportsDetailedGeometry = reportsGeometry
            && dragGeometry.shouldCollectDetailedGeometry(
                spaceId: geometrySpaceId,
                profileId: effectiveProfileId
            )
        let animationsAllowed = animateLayout && isActiveWindow && !isTransitioningProfile && !shouldReduceMotion
        shouldAnimateDropLayout = animationsAllowed
            && dragPresentation.shouldAnimateDropLayout
        shouldAnimateContentLayout = animationsAllowed
    }

    var isHoveringThisEssentials: Bool {
        guard dragPresentation.isDropProjectionActive,
              case .essentials = dragPresentation.projectionHoveredSlot else {
            return false
        }
        return true
    }

    /// The hint stands in for the drag-hover reveal: while the placeholder is on
    /// screen it already is the drop target, so there is no separate gap to open.
    var emptyPresentation: EmptyPresentation {
        guard items.isEmpty else { return .collapsed }
        if showsHint { return .placeholder }
        return isHoveringThisEssentials && projectedLayout.canAcceptDrop
            ? .placeholder
            : .collapsed
    }

    var revealTileSize: CGSize {
        projectedLayout.rows.first?.tileSize ?? projectedLayout.tileSize
    }

    var revealHeight: CGFloat {
        emptyPresentation == .placeholder
            ? EssentialsPlaceholderMetrics.height
            : PinnedTileMetrics.collapsedEssentialsRevealHeight
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
                dragPresentation: dragPresentation
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
        dragPresentation.previewState(for: geometrySpaceId).flatMap {
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
