//
//  ExtensionActionReorderSurface.swift
//  Sumi
//
//  Shared drag-to-reorder chrome for the three extension-action surfaces
//  (hub tiles, sidebar grid, compact strip): gesture, overlay, spring, and
//  post-drop activation suppression. Layout, item models, and commit targets
//  stay with the thin wrappers.
//

import SwiftUI

@available(macOS 15.5, *)
enum ExtensionActionReorderMetrics {
    /// After a reorder drop, suppress the synthetic click that would otherwise
    /// open the extension action popup.
    static let activationSuppressInterval: TimeInterval = 0.25
    static let springAnimation = Animation.interactiveSpring(
        duration: 0.22,
        extraBounce: 0.05
    )
}

@available(macOS 15.5, *)
struct ExtensionActionReorderSurface<Item>: View {
    let base: [Item]
    let id: KeyPath<Item, String>
    let axis: ReorderAxis
    let coordinateSpaceName: String
    let onCommit: (ReorderMove<String>) -> Void
    private let content: (Surface) -> AnyView
    private let overlayContent: (Item) -> AnyView

    @State private var reorder = ReorderDragState<String>()
    @State private var frames = ReorderFrameStore()
    @State private var lastDropAt = Date.distantPast

    init(
        base: [Item],
        id: KeyPath<Item, String>,
        axis: ReorderAxis,
        coordinateSpaceName: String,
        onCommit: @escaping (ReorderMove<String>) -> Void,
        @ViewBuilder content: @escaping (Surface) -> some View,
        @ViewBuilder overlayContent: @escaping (Item) -> some View
    ) {
        self.base = base
        self.id = id
        self.axis = axis
        self.coordinateSpaceName = coordinateSpaceName
        self.onCommit = onCommit
        self.content = { AnyView(content($0)) }
        self.overlayContent = { AnyView(overlayContent($0)) }
    }

    var body: some View {
        let itemID = id
        let baseIDs = base.map { $0[keyPath: itemID] }
        let displayed = reorder.displayOrder(base) { $0[keyPath: itemID] }
        let surface = Surface(
            displayed: displayed,
            baseIDs: baseIDs,
            itemID: itemID,
            reorder: reorder,
            shouldSuppressActivation: { shouldSuppressActivation },
            coordinateSpaceName: coordinateSpaceName,
            axis: axis,
            frames: $frames,
            reorderState: $reorder,
            onBeginDrag: { frames.freeze(order: baseIDs) },
            onEndDrag: { lastDropAt = Date() },
            onCommit: onCommit
        )

        content(surface)
            .coordinateSpace(name: coordinateSpaceName)
            .overlay(alignment: .topLeading) { draggedOverlay(displayed) }
            .animation(
                ExtensionActionReorderMetrics.springAnimation,
                value: displayed.map { $0[keyPath: itemID] }
            )
    }

    @ViewBuilder
    private func draggedOverlay(_ items: [Item]) -> some View {
        if let draggedID = reorder.draggedID,
           let item = items.first(where: { $0[keyPath: id] == draggedID }),
           let frame = reorder.draggedOverlayFrame() {
            overlayContent(item)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
                .animation(nil, value: reorder.currentLocation)
                .zIndex(2)
        }
    }

    private var shouldSuppressActivation: Bool {
        Date().timeIntervalSince(lastDropAt)
            < ExtensionActionReorderMetrics.activationSuppressInterval
    }

    @MainActor
    struct Surface {
        let displayed: [Item]
        let baseIDs: [String]
        let itemID: KeyPath<Item, String>
        let reorder: ReorderDragState<String>
        let shouldSuppressActivation: () -> Bool
        let coordinateSpaceName: String
        let axis: ReorderAxis
        @Binding var frames: ReorderFrameStore
        @Binding var reorderState: ReorderDragState<String>
        let onBeginDrag: () -> Void
        let onEndDrag: () -> Void
        let onCommit: (ReorderMove<String>) -> Void

        func slotID(_ item: Item) -> String {
            item[keyPath: itemID]
        }

        @ViewBuilder
        func slot(
            _ item: Item,
            @ViewBuilder content: () -> some View
        ) -> some View {
            let slotID = self.slotID(item)
            content()
                .opacity(reorder.hidesInlineItem(slotID) ? 0 : 1)
                .reorderSlotFrame(
                    id: slotID,
                    coordinateSpace: coordinateSpaceName,
                    into: $frames.live
                )
                .simultaneousGesture(reorderGesture(for: slotID))
        }

        private func reorderGesture(for id: String) -> some Gesture {
            makeReorderDragGesture(
                id: id,
                coordinateSpaceName: coordinateSpaceName,
                isEnabled: { baseIDs.count > 1 },
                orderedIDs: { baseIDs },
                geometry: {
                    frames.geometry(
                        axis: axis,
                        isDragging: reorderState.isDragging,
                        baseOrder: baseIDs
                    )
                },
                state: $reorderState,
                onBeginDrag: onBeginDrag,
                onEndDrag: onEndDrag,
                onCommit: onCommit
            )
        }
    }
}
