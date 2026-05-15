//
//  SpaceReorderDragState.swift
//  Sumi
//

import SwiftUI

enum SpaceReorderCoordinateSpace {
    static let name = "spaces-list-reorder-coordinate-space"
}

struct SpaceStripMetrics: Equatable {
    let slotSize: CGFloat
    let dotSize: CGFloat
    let minSpacing: CGFloat
    let maxSpacing: CGFloat
    let cornerRadius: CGFloat

    static func resolve(for controlSize: ControlSize) -> Self {
        Self(
            slotSize: slotSize(for: controlSize),
            dotSize: 6,
            minSpacing: 1,
            maxSpacing: 8,
            cornerRadius: 8
        )
    }

    private static func slotSize(for controlSize: ControlSize) -> CGFloat {
        switch controlSize {
        case .mini: 24
        case .small: 28
        case .regular: 32
        case .large: 40
        case .extraLarge: 48
        @unknown default: 32
        }
    }
}

struct SpaceStripGeometry: Equatable {
    let slotFrames: [CGRect]
    let spacing: CGFloat
    let contentFrame: CGRect

    static func make(
        itemCount: Int,
        availableWidth: CGFloat,
        metrics: SpaceStripMetrics
    ) -> Self {
        guard itemCount > 0 else {
            return Self(slotFrames: [], spacing: 0, contentFrame: .zero)
        }

        let spacing: CGFloat
        if itemCount == 1 {
            spacing = 0
        } else {
            let proposedSpacing = (availableWidth - (CGFloat(itemCount) * metrics.slotSize)) / CGFloat(itemCount - 1)
            spacing = min(max(proposedSpacing, metrics.minSpacing), metrics.maxSpacing)
        }

        let contentWidth = (CGFloat(itemCount) * metrics.slotSize)
            + (CGFloat(max(itemCount - 1, 0)) * spacing)
        let originX = (availableWidth - contentWidth) / 2
        let frames = (0..<itemCount).map { index in
            CGRect(
                x: originX + (CGFloat(index) * (metrics.slotSize + spacing)),
                y: 0,
                width: metrics.slotSize,
                height: metrics.slotSize
            )
        }

        return Self(
            slotFrames: frames,
            spacing: spacing,
            contentFrame: CGRect(x: originX, y: 0, width: contentWidth, height: metrics.slotSize)
        )
    }

    func frame(at index: Int) -> CGRect? {
        guard slotFrames.indices.contains(index) else { return nil }
        return slotFrames[index]
    }

    func insertionIndex(for draggedCenterX: CGFloat, excluding originIndex: Int) -> Int {
        slotFrames.enumerated().reduce(into: 0) { insertionIndex, entry in
            guard entry.offset != originIndex else { return }
            if draggedCenterX > entry.element.midX {
                insertionIndex += 1
            }
        }
    }
}

struct SpaceStripLayout: Layout {
    let metrics: SpaceStripMetrics

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let minimumWidth = (CGFloat(subviews.count) * metrics.slotSize)
            + (CGFloat(max(subviews.count - 1, 0)) * metrics.minSpacing)
        return CGSize(
            width: proposal.width ?? minimumWidth,
            height: metrics.slotSize
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let geometry = SpaceStripGeometry.make(
            itemCount: subviews.count,
            availableWidth: bounds.width,
            metrics: metrics
        )

        for (index, subview) in subviews.enumerated() {
            guard let frame = geometry.frame(at: index) else { continue }
            subview.place(
                at: CGPoint(x: bounds.minX + frame.midX, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}

struct SpaceReorderDrop: Equatable {
    let spaceId: UUID
    let targetIndex: Int
}

struct SpaceReorderDragState: Equatable {
    static let dragThreshold: CGFloat = 6

    var draggedSpaceId: UUID?
    var startLocation: CGPoint = .zero
    var currentLocation: CGPoint = .zero
    var hasCrossedDragThreshold = false
    var originOrder: [UUID] = []
    var visualOrder: [UUID]?
    var dragGrabOffsetX: CGFloat = 0
    var dragGeometry: SpaceStripGeometry?
    var suppressedClickSpaceId: UUID?

    var isDragging: Bool {
        draggedSpaceId != nil && hasCrossedDragThreshold
    }

    var isTrackingDrag: Bool {
        draggedSpaceId != nil
    }

    mutating func begin(
        spaceId: UUID,
        location: CGPoint,
        orderedSpaceIds: [UUID],
        geometry: SpaceStripGeometry
    ) {
        guard draggedSpaceId == nil,
              let draggedIndex = orderedSpaceIds.firstIndex(of: spaceId),
              let draggedFrame = geometry.frame(at: draggedIndex)
        else { return }

        draggedSpaceId = spaceId
        startLocation = location
        currentLocation = location
        hasCrossedDragThreshold = false
        originOrder = orderedSpaceIds
        visualOrder = nil
        dragGeometry = geometry
        dragGrabOffsetX = location.x - draggedFrame.midX
    }

    mutating func update(
        spaceId: UUID,
        location: CGPoint,
        orderedSpaceIds: [UUID],
        geometry: SpaceStripGeometry
    ) -> (didBeginDrag: Bool, didReorder: Bool) {
        if draggedSpaceId == nil {
            begin(
                spaceId: spaceId,
                location: location,
                orderedSpaceIds: orderedSpaceIds,
                geometry: geometry
            )
        }
        guard draggedSpaceId == spaceId else {
            return (false, false)
        }

        currentLocation = location
        let crossedBefore = hasCrossedDragThreshold
        if !hasCrossedDragThreshold,
           distance(from: startLocation, to: location) >= Self.dragThreshold
        {
            hasCrossedDragThreshold = true
            visualOrder = originOrder
        }

        guard hasCrossedDragThreshold else {
            return (false, false)
        }

        let didReorder = updateVisualOrder()
        return (!crossedBefore, didReorder)
    }

    mutating func finish() -> SpaceReorderDrop? {
        defer { clearDragSession() }

        guard hasCrossedDragThreshold,
              let draggedSpaceId,
              let visualOrder,
              let targetIndex = visualOrder.firstIndex(of: draggedSpaceId)
        else {
            return nil
        }

        suppressedClickSpaceId = draggedSpaceId
        return SpaceReorderDrop(spaceId: draggedSpaceId, targetIndex: targetIndex)
    }

    mutating func reset() {
        clearDragSession()
    }

    mutating func consumeSuppressedClick(for spaceId: UUID) -> Bool {
        guard suppressedClickSpaceId == spaceId else { return false }
        suppressedClickSpaceId = nil
        return true
    }

    func hidesInlineSpace(_ spaceId: UUID) -> Bool {
        isTrackingDrag && draggedSpaceId == spaceId
    }

    func draggedOverlayFrame() -> CGRect? {
        guard let draggedSpaceId,
              let draggedIndex = originOrder.firstIndex(of: draggedSpaceId),
              let frame = dragGeometry?.frame(at: draggedIndex)
        else {
            return nil
        }

        let centerX = draggedOverlayCenterX()
        return CGRect(
            x: centerX - (frame.width / 2),
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }

    private mutating func updateVisualOrder() -> Bool {
        guard let draggedSpaceId,
              let dragGeometry,
              originOrder.contains(draggedSpaceId)
        else {
            return false
        }

        guard let draggedOriginIndex = originOrder.firstIndex(of: draggedSpaceId) else {
            return false
        }

        var nextOrder = originOrder.filter { $0 != draggedSpaceId }
        let draggedCenterX = clampedDraggedCenterX(in: dragGeometry)
        let targetIndex = dragGeometry.insertionIndex(
            for: draggedCenterX,
            excluding: draggedOriginIndex
        )
        nextOrder.insert(draggedSpaceId, at: targetIndex)
        guard nextOrder != visualOrder else { return false }
        visualOrder = nextOrder
        return true
    }

    private mutating func clearDragSession() {
        draggedSpaceId = nil
        hasCrossedDragThreshold = false
        originOrder = []
        visualOrder = nil
        dragGrabOffsetX = 0
        dragGeometry = nil
    }

    private func draggedOverlayCenterX() -> CGFloat {
        currentLocation.x - dragGrabOffsetX
    }

    private func clampedDraggedCenterX(in geometry: SpaceStripGeometry) -> CGFloat {
        guard let firstFrame = geometry.slotFrames.first,
              let lastFrame = geometry.slotFrames.last
        else {
            return draggedOverlayCenterX()
        }
        return min(max(draggedOverlayCenterX(), firstFrame.midX - 0.5), lastFrame.midX + 0.5)
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}
