//
//  ReorderDragState.swift
//  Sumi
//
//  Generic, value-type drag-to-reorder state machine shared by every
//  reorderable surface. Ported from the sidebar spaces implementation and
//  generalized over the item identifier type and layout axis.
//
//  The state is intentionally a plain `Equatable` struct so it can live in
//  SwiftUI `@State` with zero allocation and cheap diffing. No model writes or
//  persistence happen while dragging: only `visualOrder` mutates, and callers
//  commit the final `ReorderMove` once on drop.
//

import CoreGraphics

/// The result of a completed reorder drag: which item moved and its target
/// index in the committed order.
struct ReorderMove<ID: Hashable>: Equatable {
    let id: ID
    let targetIndex: Int
}

struct ReorderDragState<ID: Hashable>: Equatable {
    /// Pointer travel (in points) required before a press becomes a drag. Kept
    /// low enough to feel responsive while still letting a tap through.
    static var dragThreshold: CGFloat { 6 }

    private(set) var draggedID: ID?
    var startLocation: CGPoint = .zero
    var currentLocation: CGPoint = .zero
    private(set) var hasCrossedDragThreshold = false
    private(set) var originOrder: [ID] = []
    private(set) var visualOrder: [ID]?
    private var grabOffset: CGSize = .zero
    private var dragGeometry: ReorderGeometry?
    private(set) var suppressedClickID: ID?
    private let threshold: CGFloat

    init(threshold: CGFloat = ReorderDragState.dragThreshold) {
        self.threshold = threshold
    }

    /// True once the press has become an actual drag (crossed the threshold).
    var isDragging: Bool { draggedID != nil && hasCrossedDragThreshold }

    /// True while a press on an item is being tracked, before/after threshold.
    var isTrackingDrag: Bool { draggedID != nil }

    /// Origin index of the dragged item in the pre-drag order.
    var draggedSourceIndex: Int? {
        guard let draggedID else { return nil }
        return originOrder.firstIndex(of: draggedID)
    }

    /// Projected index of the dragged item in the live visual order.
    var draggedProjectedIndex: Int? {
        guard let draggedID, let visualOrder else { return nil }
        return visualOrder.firstIndex(of: draggedID)
    }

    // MARK: - Drag lifecycle

    /// Feed a pointer sample. Begins tracking on the first sample. Returns
    /// whether this sample started the drag and whether the visual order moved,
    /// so callers can skip redundant work / state publishes.
    mutating func update(
        id: ID,
        location: CGPoint,
        orderedIDs: [ID],
        geometry: ReorderGeometry
    ) -> (didBeginDrag: Bool, didReorder: Bool) {
        if draggedID == nil {
            begin(id: id, location: location, orderedIDs: orderedIDs, geometry: geometry)
        }
        guard draggedID == id else { return (false, false) }

        currentLocation = location
        dragGeometry = geometry

        let crossedBefore = hasCrossedDragThreshold
        if !hasCrossedDragThreshold,
           distance(from: startLocation, to: location) >= threshold {
            hasCrossedDragThreshold = true
            visualOrder = originOrder
        }

        guard hasCrossedDragThreshold else { return (false, false) }

        let didReorder = updateVisualOrder()
        return (!crossedBefore, didReorder)
    }

    /// Complete the drag. Returns the committed move (and arms a one-shot click
    /// suppression) when the item actually moved past the threshold.
    mutating func finish() -> ReorderMove<ID>? {
        defer { clearDragSession() }

        guard hasCrossedDragThreshold,
              let draggedID,
              let visualOrder,
              let targetIndex = visualOrder.firstIndex(of: draggedID)
        else {
            return nil
        }

        suppressedClickID = draggedID
        return ReorderMove(id: draggedID, targetIndex: targetIndex)
    }

    mutating func reset() {
        clearDragSession()
    }

    /// Consume the synthetic click a completed drag would otherwise fire.
    mutating func consumeSuppressedClick(for id: ID) -> Bool {
        guard suppressedClickID == id else { return false }
        suppressedClickID = nil
        return true
    }

    // MARK: - Rendering helpers

    /// Whether the inline slot for `id` should be hidden (it is being dragged
    /// and rendered in the floating overlay instead).
    ///
    /// Gated on `isDragging`, not `isTrackingDrag`: gestures are built with
    /// `minimumDistance: 0`, so tracking begins on the first mouse-down sample.
    /// Hiding there would blank the slot on every plain click — and any AppKit
    /// view hosted inside it (an `NSPopover` anchor, say) would report
    /// `alphaValue == 0` at the moment the click resolves.
    func hidesInlineItem(_ id: ID) -> Bool {
        isDragging && draggedID == id
    }

    /// The items reordered to match the live visual order during a drag, or the
    /// input untouched when no drag is in progress.
    func displayOrder<Item>(_ items: [Item], id keyPath: (Item) -> ID) -> [Item] {
        guard let visualOrder else { return items }

        let itemsByID = Dictionary(items.map { (keyPath($0), $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = visualOrder.compactMap { itemsByID[$0] }
        let orderedIDs = Set(visualOrder)
        return ordered + items.filter { !orderedIDs.contains(keyPath($0)) }
    }

    /// The floating overlay frame for the dragged item, following the cursor
    /// along the reorder axis (unclamped, so it can leave the strip bounds).
    func draggedOverlayFrame() -> CGRect? {
        guard let draggedID,
              let originIndex = originOrder.firstIndex(of: draggedID),
              let base = dragGeometry?.frame(at: originIndex)
        else {
            return nil
        }

        let origin = overlayOrigin()
        switch dragGeometry?.axis ?? .horizontal {
        case .horizontal:
            return CGRect(x: origin.x, y: base.minY, width: base.width, height: base.height)
        case .vertical:
            return CGRect(x: base.minX, y: origin.y, width: base.width, height: base.height)
        case .grid:
            return CGRect(x: origin.x, y: origin.y, width: base.width, height: base.height)
        }
    }

    // MARK: - Private

    private mutating func begin(
        id: ID,
        location: CGPoint,
        orderedIDs: [ID],
        geometry: ReorderGeometry
    ) {
        guard draggedID == nil,
              let index = orderedIDs.firstIndex(of: id),
              let frame = geometry.frame(at: index)
        else { return }

        draggedID = id
        startLocation = location
        currentLocation = location
        hasCrossedDragThreshold = false
        originOrder = orderedIDs
        visualOrder = nil
        dragGeometry = geometry
        grabOffset = CGSize(
            width: location.x - frame.minX,
            height: location.y - frame.minY
        )
    }

    private mutating func updateVisualOrder() -> Bool {
        guard let draggedID,
              let dragGeometry,
              let originIndex = originOrder.firstIndex(of: draggedID)
        else {
            return false
        }

        var nextOrder = originOrder.filter { $0 != draggedID }
        let center = dragGeometry.clampedInsertionCenter(draggedCenter())
        let targetIndex = dragGeometry.insertionIndex(for: center, excluding: originIndex)
        let clampedTarget = min(max(targetIndex, 0), nextOrder.count)
        nextOrder.insert(draggedID, at: clampedTarget)

        guard nextOrder != visualOrder else { return false }
        visualOrder = nextOrder
        return true
    }

    private mutating func clearDragSession() {
        draggedID = nil
        hasCrossedDragThreshold = false
        originOrder = []
        visualOrder = nil
        grabOffset = .zero
        dragGeometry = nil
    }

    /// Top-left of the floating overlay, following the cursor unclamped.
    private func overlayOrigin() -> CGPoint {
        CGPoint(
            x: currentLocation.x - grabOffset.width,
            y: currentLocation.y - grabOffset.height
        )
    }

    /// Center of the dragged slot, used for insertion hit-testing.
    private func draggedCenter() -> CGPoint {
        let origin = overlayOrigin()
        guard let draggedID,
              let originIndex = originOrder.firstIndex(of: draggedID),
              let base = dragGeometry?.frame(at: originIndex)
        else {
            return origin
        }
        return CGPoint(x: origin.x + base.width / 2, y: origin.y + base.height / 2)
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}
