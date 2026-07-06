//
//  ReorderInteraction.swift
//  Sumi
//
//  SwiftUI glue shared by every drag-to-reorder surface: the drag-gesture
//  builder and a lightweight per-slot frame reporter. The visual presentation
//  (row vs. grid, overlay styling, sibling animation) stays with each surface;
//  only the interaction logic is unified here.
//

import SwiftUI

extension View {
    /// Report this slot's frame (in the given reorder coordinate space) into a
    /// frame dictionary keyed by item id. Uses `onGeometryChange`, so it only
    /// fires when the frame actually changes — no per-frame polling.
    func reorderSlotFrame<ID: Hashable>(
        id: ID,
        coordinateSpace name: String,
        into frames: Binding<[ID: CGRect]>
    ) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(name))
        } action: { newFrame in
            frames.wrappedValue[id] = newFrame
        }
    }
}

/// Captured slot frames for a reorderable surface whose geometry is measured
/// (rather than computed by a deterministic `Layout`). Live frames update as
/// the surface lays out; on drag begin they are frozen so insertion decisions
/// stay stable while siblings animate to their reflowed positions.
struct ReorderFrameStore: Equatable {
    var live: [String: CGRect] = [:]
    private var frozen: [String: CGRect] = [:]
    private var frozenOrder: [String] = []

    /// Snapshot the current live frames as the fixed slot geometry for a drag.
    mutating func freeze(order: [String]) {
        frozen = live
        frozenOrder = order
    }

    /// Geometry for the surface: frozen slots while dragging, live otherwise.
    func geometry(
        axis: ReorderAxis,
        isDragging: Bool,
        baseOrder: [String]
    ) -> ReorderGeometry {
        if isDragging, frozenOrder.isEmpty == false {
            return ReorderGeometry(
                axis: axis,
                slotFrames: frozenOrder.compactMap { frozen[$0] }
            )
        }
        return ReorderGeometry(
            axis: axis,
            slotFrames: baseOrder.compactMap { live[$0] }
        )
    }
}

/// Build the drag gesture for a single reorderable item. Faithful
/// generalization of the sidebar-spaces gesture: below the threshold the
/// press is treated as a tap (`onTap`); past it, the item reorders and the
/// final position is committed once via `onCommit`.
@MainActor
func makeReorderDragGesture<ID: Hashable>(
    id: ID,
    coordinateSpaceName: String,
    minimumDistance: CGFloat = 0,
    isEnabled: @escaping () -> Bool,
    orderedIDs: @escaping () -> [ID],
    geometry: @escaping () -> ReorderGeometry,
    state: Binding<ReorderDragState<ID>>,
    onBeginDrag: @escaping () -> Void = {},
    onEndDrag: @escaping () -> Void = {},
    onCommit: @escaping (ReorderMove<ID>) -> Void,
    onTap: @escaping () -> Void = {}
) -> some Gesture {
    DragGesture(minimumDistance: minimumDistance, coordinateSpace: .named(coordinateSpaceName))
        .onChanged { value in
            guard isEnabled() else { return }
            let result = state.wrappedValue.update(
                id: id,
                location: value.location,
                orderedIDs: orderedIDs(),
                geometry: geometry()
            )
            if result.didBeginDrag {
                onBeginDrag()
            }
        }
        .onEnded { value in
            guard isEnabled() else {
                if reorderDragDistance(value) < ReorderDragState<ID>.dragThreshold {
                    onTap()
                }
                return
            }

            let wasDragging = state.wrappedValue.isDragging
            let move = state.wrappedValue.finish()
            if wasDragging {
                onEndDrag()
            }
            if let move {
                onCommit(move)
            } else if !wasDragging {
                onTap()
            }
        }
}

@MainActor
private func reorderDragDistance(_ value: DragGesture.Value) -> CGFloat {
    hypot(value.translation.width, value.translation.height)
}
