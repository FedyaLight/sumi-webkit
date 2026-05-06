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
    private static let dragThreshold: CGFloat = 6
    private static let markerWidth: CGFloat = 2
    private static let markerHorizontalInset: CGFloat = 3

    var draggedSpaceId: UUID?
    var startLocation: CGPoint = .zero
    var currentLocation: CGPoint = .zero
    var hasCrossedDragThreshold = false
    var itemFrames: [UUID: CGRect] = [:]
    var targetInsertionIndex: Int?
    var visualInsertionIndex: Int?
    var suppressedClickSpaceId: UUID?

    var isDragging: Bool {
        draggedSpaceId != nil && hasCrossedDragThreshold
    }

    mutating func updateItemFrames(_ frames: [UUID: CGRect]) {
        itemFrames = frames
    }

    mutating func begin(spaceId: UUID, location: CGPoint) {
        guard draggedSpaceId == nil else { return }
        draggedSpaceId = spaceId
        startLocation = location
        currentLocation = location
        hasCrossedDragThreshold = false
        targetInsertionIndex = nil
        visualInsertionIndex = nil
    }

    mutating func update(
        spaceId: UUID,
        location: CGPoint,
        orderedSpaceIds: [UUID]
    ) -> Bool {
        if draggedSpaceId == nil {
            begin(spaceId: spaceId, location: location)
        }
        guard draggedSpaceId == spaceId else { return false }

        currentLocation = location
        let crossedBefore = hasCrossedDragThreshold
        if !hasCrossedDragThreshold,
           distance(from: startLocation, to: location) >= Self.dragThreshold
        {
            hasCrossedDragThreshold = true
        }

        guard hasCrossedDragThreshold else { return false }
        updateInsertionIndices(orderedSpaceIds: orderedSpaceIds)
        return !crossedBefore
    }

    mutating func finish(orderedSpaceIds: [UUID]) -> SpaceReorderDrop? {
        defer {
            draggedSpaceId = nil
            hasCrossedDragThreshold = false
            targetInsertionIndex = nil
            visualInsertionIndex = nil
        }

        guard hasCrossedDragThreshold,
              let draggedSpaceId,
              orderedSpaceIds.contains(draggedSpaceId)
        else {
            return nil
        }

        suppressedClickSpaceId = draggedSpaceId
        updateInsertionIndices(orderedSpaceIds: orderedSpaceIds)
        guard let targetInsertionIndex else { return nil }
        return SpaceReorderDrop(spaceId: draggedSpaceId, targetIndex: targetInsertionIndex)
    }

    mutating func reset() {
        draggedSpaceId = nil
        hasCrossedDragThreshold = false
        targetInsertionIndex = nil
        visualInsertionIndex = nil
    }

    mutating func consumeSuppressedClick(for spaceId: UUID) -> Bool {
        guard suppressedClickSpaceId == spaceId else { return false }
        suppressedClickSpaceId = nil
        return true
    }

    func markerFrame(orderedSpaceIds: [UUID]) -> CGRect? {
        guard isDragging,
              let visualInsertionIndex,
              let firstFrame = orderedFrames(orderedSpaceIds: orderedSpaceIds).first?.frame
        else {
            return nil
        }

        let frames = orderedFrames(orderedSpaceIds: orderedSpaceIds)
        guard !frames.isEmpty else { return nil }

        let markerX: CGFloat
        if visualInsertionIndex <= 0 {
            markerX = frames[0].frame.minX - Self.markerHorizontalInset
        } else if visualInsertionIndex >= frames.count {
            markerX = frames[frames.count - 1].frame.maxX + Self.markerHorizontalInset
        } else {
            let previousFrame = frames[visualInsertionIndex - 1].frame
            let nextFrame = frames[visualInsertionIndex].frame
            markerX = (previousFrame.maxX + nextFrame.minX) / 2
        }

        let height = min(max(firstFrame.height - 8, 16), 24)
        return CGRect(
            x: markerX - (Self.markerWidth / 2),
            y: firstFrame.midY - (height / 2),
            width: Self.markerWidth,
            height: height
        )
    }

    private mutating func updateInsertionIndices(orderedSpaceIds: [UUID]) {
        guard let draggedSpaceId,
              let sourceIndex = orderedSpaceIds.firstIndex(of: draggedSpaceId),
              let insertionSlot = visualInsertionSlot(orderedSpaceIds: orderedSpaceIds)
        else {
            targetInsertionIndex = nil
            visualInsertionIndex = nil
            return
        }

        visualInsertionIndex = insertionSlot
        targetInsertionIndex = sourceIndex < insertionSlot ? insertionSlot - 1 : insertionSlot
    }

    private func visualInsertionSlot(orderedSpaceIds: [UUID]) -> Int? {
        let frames = orderedFrames(orderedSpaceIds: orderedSpaceIds)
        guard !frames.isEmpty else { return nil }

        for (index, item) in frames.enumerated() where currentLocation.x < item.frame.midX {
            return index
        }
        return frames.count
    }

    private func orderedFrames(orderedSpaceIds: [UUID]) -> [(id: UUID, frame: CGRect)] {
        orderedSpaceIds.compactMap { id in
            guard let frame = itemFrames[id], frame.isNull == false else { return nil }
            return (id, frame)
        }
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
