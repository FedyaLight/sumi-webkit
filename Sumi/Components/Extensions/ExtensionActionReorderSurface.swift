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
    /// Primary activation for a slot. Delivered by the reorder gesture's tap
    /// branch rather than a nested `Button`: the gesture is built with
    /// `minimumDistance: 0` and needs the primary mouse, so a button inside it
    /// would be a second claimant on the same press.
    let onActivate: (Item) -> Void
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
        onActivate: @escaping (Item) -> Void,
        @ViewBuilder content: @escaping (Surface) -> some View,
        @ViewBuilder overlayContent: @escaping (Item) -> some View
    ) {
        self.base = base
        self.id = id
        self.axis = axis
        self.coordinateSpaceName = coordinateSpaceName
        self.onCommit = onCommit
        self.onActivate = onActivate
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
            onCommit: onCommit,
            onActivate: onActivate
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
        // Only past the drag threshold: below it the inline slot is still
        // visible (see `ReorderDragState.hidesInlineItem`), so a floating copy
        // here would double the icon on every plain press.
        if reorder.isDragging,
           let draggedID = reorder.draggedID,
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
        let onActivate: (Item) -> Void

        func slotID(_ item: Item) -> String {
            item[keyPath: itemID]
        }

        /// Whether the slot is currently under the pointer with the button
        /// down, drag threshold crossed or not. Replaces the per-button press
        /// gesture that used to compete with this one.
        func isPressed(_ item: Item) -> Bool {
            reorder.isTrackingDrag && reorder.draggedID == slotID(item)
        }

        @ViewBuilder
        func slot(
            _ item: Item,
            @ViewBuilder content: () -> some View
        ) -> some View {
            let slotID = self.slotID(item)
            content()
                .opacity(reorder.hidesInlineItem(slotID) ? 0 : 1)
                .contentShape(Rectangle())
                .reorderSlotFrame(
                    id: slotID,
                    coordinateSpace: coordinateSpaceName,
                    into: $frames.live
                )
                .gesture(reorderGesture(for: item))
        }

        private func reorderGesture(for item: Item) -> some Gesture {
            makeReorderDragGesture(
                id: slotID(item),
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
                onCommit: onCommit,
                onTap: {
                    guard shouldSuppressActivation() == false else { return }
                    onActivate(item)
                }
            )
        }
    }
}
