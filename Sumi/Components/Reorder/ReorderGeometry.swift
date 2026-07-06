//
//  ReorderGeometry.swift
//  Sumi
//
//  Axis-aware slot geometry shared by every drag-to-reorder surface
//  (sidebar spaces, settings search engines, pinned/unpinned extension
//  actions). Holds the laid-out slot frames and resolves where a dragged
//  item should be inserted for a given pointer position.
//

import CoreGraphics

/// The layout direction a reorderable surface flows in.
enum ReorderAxis: Equatable {
    /// Single horizontal row (spaces strip, pinned extension row).
    case horizontal
    /// Single vertical column (settings search-engine list).
    case vertical
    /// Wrapping multi-row grid, read in row-major order (hub tiles).
    case grid
}

/// Immutable snapshot of the slot frames for a reorderable surface plus the
/// insertion math that maps a dragged pointer position onto a target index.
///
/// Frames are expressed in the surface's own reorder coordinate space and are
/// ordered to match the currently displayed item order.
struct ReorderGeometry: Equatable {
    let axis: ReorderAxis
    let slotFrames: [CGRect]

    init(axis: ReorderAxis, slotFrames: [CGRect]) {
        self.axis = axis
        self.slotFrames = slotFrames
    }

    var isEmpty: Bool { slotFrames.isEmpty }

    func frame(at index: Int) -> CGRect? {
        guard slotFrames.indices.contains(index) else { return nil }
        return slotFrames[index]
    }

    /// The index the dragged item should occupy given its (already clamped)
    /// center point, ignoring the slot it currently originates from.
    func insertionIndex(for draggedCenter: CGPoint, excluding originIndex: Int) -> Int {
        slotFrames.enumerated().reduce(into: 0) { insertionIndex, entry in
            guard entry.offset != originIndex else { return }
            if slot(entry.element, precedes: draggedCenter) {
                insertionIndex += 1
            }
        }
    }

    /// Clamp a raw dragged center so insertion decisions stay stable when the
    /// pointer travels past the ends of the strip. The floating overlay keeps
    /// following the cursor unclamped; only the insertion math is bounded.
    func clampedInsertionCenter(_ center: CGPoint) -> CGPoint {
        guard let first = slotFrames.first, let last = slotFrames.last else {
            return center
        }

        switch axis {
        case .horizontal:
            let x = min(max(center.x, first.midX - 0.5), last.midX + 0.5)
            return CGPoint(x: x, y: center.y)
        case .vertical:
            let y = min(max(center.y, first.midY - 0.5), last.midY + 0.5)
            return CGPoint(x: center.x, y: y)
        case .grid:
            let midXs = slotFrames.map(\.midX)
            let midYs = slotFrames.map(\.midY)
            let minX = (midXs.min() ?? center.x) - 0.5
            let maxX = (midXs.max() ?? center.x) + 0.5
            let minY = (midYs.min() ?? center.y) - 0.5
            let maxY = (midYs.max() ?? center.y) + 0.5
            return CGPoint(
                x: min(max(center.x, minX), maxX),
                y: min(max(center.y, minY), maxY)
            )
        }
    }

    private func slot(_ frame: CGRect, precedes point: CGPoint) -> Bool {
        switch axis {
        case .horizontal:
            return point.x > frame.midX
        case .vertical:
            return point.y > frame.midY
        case .grid:
            // Earlier row → precedes; later row → follows; same row → compare X.
            if point.y > frame.maxY { return true }
            if point.y < frame.minY { return false }
            return point.x > frame.midX
        }
    }
}
