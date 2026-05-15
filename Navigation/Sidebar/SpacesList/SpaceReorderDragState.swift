//
//  SpaceReorderDragState.swift
//  Sumi
//

import SwiftUI

enum SpaceReorderCoordinateSpace {
    static let name = "spaces-list-reorder-coordinate-space"
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
    var itemFrames: [UUID: CGRect] = [:]
    var dragStartItemFrames: [UUID: CGRect] = [:]
    var dragStartOrderedSpaceIds: [UUID] = []
    var visualOrder: [UUID]?
    var dragGrabOffsetX: CGFloat = 0
    var suppressedClickSpaceId: UUID?

    var isDragging: Bool {
        draggedSpaceId != nil && hasCrossedDragThreshold
    }

    var isTrackingDrag: Bool {
        draggedSpaceId != nil
    }

    mutating func updateItemFrames(_ frames: [UUID: CGRect]) {
        itemFrames = frames
    }

    mutating func begin(spaceId: UUID, location: CGPoint, orderedSpaceIds: [UUID]) {
        guard draggedSpaceId == nil else { return }
        draggedSpaceId = spaceId
        startLocation = location
        currentLocation = location
        hasCrossedDragThreshold = false
        dragStartItemFrames = itemFrames
        dragStartOrderedSpaceIds = orderedSpaceIds
        visualOrder = nil
        if let frame = itemFrames[spaceId], frame.isNull == false {
            dragGrabOffsetX = location.x - frame.midX
        } else {
            dragGrabOffsetX = 0
        }
    }

    mutating func update(
        spaceId: UUID,
        location: CGPoint,
        orderedSpaceIds: [UUID]
    ) -> (didBeginDrag: Bool, didReorder: Bool) {
        if draggedSpaceId == nil {
            begin(spaceId: spaceId, location: location, orderedSpaceIds: orderedSpaceIds)
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
            visualOrder = orderedSpaceIds
        }

        guard hasCrossedDragThreshold else {
            return (false, false)
        }

        let didReorder = updateVisualOrder(fallbackOrderedSpaceIds: orderedSpaceIds)
        return (!crossedBefore, didReorder)
    }

    mutating func finish() -> SpaceReorderDrop? {
        defer {
            draggedSpaceId = nil
            hasCrossedDragThreshold = false
            dragStartItemFrames = [:]
            dragStartOrderedSpaceIds = []
            visualOrder = nil
            dragGrabOffsetX = 0
        }

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
        draggedSpaceId = nil
        hasCrossedDragThreshold = false
        dragStartItemFrames = [:]
        dragStartOrderedSpaceIds = []
        visualOrder = nil
        dragGrabOffsetX = 0
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
              let frame = itemFrames[draggedSpaceId],
              frame.isNull == false
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

    private mutating func updateVisualOrder(fallbackOrderedSpaceIds: [UUID]) -> Bool {
        guard let draggedSpaceId else {
            return false
        }

        let currentOrder = dragStartOrderedSpaceIds.isEmpty ? fallbackOrderedSpaceIds : dragStartOrderedSpaceIds
        var nextOrder = currentOrder.filter { $0 != draggedSpaceId }
        guard nextOrder.count == currentOrder.count - 1 else {
            return false
        }

        let draggedCenterX = draggedCenterX(orderedSpaceIds: currentOrder, usesFrozenGeometry: true)
        let targetIndex = insertionIndex(
            draggedCenterX: draggedCenterX,
            orderedSpaceIdsWithoutDraggedSpace: nextOrder
        )
        nextOrder.insert(draggedSpaceId, at: targetIndex)

        guard nextOrder != visualOrder else { return false }
        visualOrder = nextOrder
        return true
    }

    private func insertionIndex(
        draggedCenterX: CGFloat,
        orderedSpaceIdsWithoutDraggedSpace: [UUID]
    ) -> Int {
        var targetIndex = 0
        for id in orderedSpaceIdsWithoutDraggedSpace {
            guard let frame = stableFrame(for: id), frame.isNull == false else { continue }
            if draggedCenterX > frame.midX {
                targetIndex += 1
            }
        }
        return targetIndex
    }

    private func draggedCenterX(orderedSpaceIds: [UUID], usesFrozenGeometry: Bool) -> CGFloat {
        let centers = orderedSpaceIds.compactMap { id -> CGFloat? in
            let frame = usesFrozenGeometry ? stableFrame(for: id) : itemFrames[id]
            guard let frame, frame.isNull == false else { return nil }
            return frame.midX
        }
        guard let minCenter = centers.min(), let maxCenter = centers.max() else {
            return currentLocation.x - dragGrabOffsetX
        }

        return clampedDraggedCenterX(minCenter: minCenter, maxCenter: maxCenter)
    }

    private func draggedOverlayCenterX() -> CGFloat {
        currentLocation.x - dragGrabOffsetX
    }

    private func clampedDraggedCenterX(minCenter: CGFloat, maxCenter: CGFloat) -> CGFloat {
        min(max(draggedOverlayCenterX(), minCenter - 0.5), maxCenter + 0.5)
    }

    private func stableFrame(for spaceId: UUID) -> CGRect? {
        dragStartItemFrames[spaceId] ?? itemFrames[spaceId]
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}

struct SpaceReorderItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] {
        [:]
    }

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

struct SpaceReorderItemFrameReporter: View {
    let spaceId: UUID

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: SpaceReorderItemFramePreferenceKey.self,
                value: [spaceId: proxy.frame(in: .named(SpaceReorderCoordinateSpace.name))]
            )
        }
    }
}
