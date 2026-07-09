//
//  SpaceStripLayout.swift
//  Sumi
//
//  Deterministic slot geometry + layout for the sidebar spaces strip,
//  mirroring Zen's workspace-icons strip: slots render at full size while they
//  fit, shrink down to `minSlotSize` as spaces are added, and past that the
//  strip switches to compact dots and scrolls horizontally. `SpaceStripScrollPolicy`
//  is the port of Zen's `scrollIntoView(inline: "nearest")` + `scroll-margin`
//  that keeps the active space in view with a peek of its neighbour. The
//  drag-to-reorder state machine itself is the shared `ReorderDragState`.
//

import SwiftUI

enum SpaceReorderCoordinateSpace {
    static let name = "spaces-list-reorder-coordinate-space"
}

struct SpaceStripMetrics: Equatable {
    let slotSize: CGFloat
    let minSlotSize: CGFloat
    let dotSize: CGFloat
    let compactDotSize: CGFloat
    let minSpacing: CGFloat
    let maxSpacing: CGFloat
    let cornerRadius: CGFloat
    /// Breathing room kept around the slot being scrolled into view, so the
    /// neighbouring space peeks in from the strip edge (Zen's `scroll-margin`).
    let scrollMargin: CGFloat

    static func resolve(for controlSize: ControlSize) -> Self {
        let slotSize = slotSize(for: controlSize)
        return Self(
            slotSize: slotSize,
            minSlotSize: (slotSize / 2).rounded(),
            dotSize: 6,
            compactDotSize: 4,
            minSpacing: 1,
            maxSpacing: 8,
            cornerRadius: 8,
            scrollMargin: 20
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

enum SpaceStripDisplayMode: Equatable {
    /// Every space shows its icon; slots are at full or shrunk width.
    case regular
    /// More spaces than fit even at minimum slot width: inactive spaces
    /// collapse to dots and the strip scrolls (Zen's `icons-overflow`).
    case compactDots
}

struct SpaceStripGeometry: Equatable {
    /// Slot frames in strip-content coordinates: centered within the viewport
    /// while the content fits, anchored at zero once the strip scrolls.
    let slotFrames: [CGRect]
    let slotWidth: CGFloat
    /// Width of the scrollable strip content; never narrower than the viewport.
    let contentWidth: CGFloat
    let displayMode: SpaceStripDisplayMode
    let isScrollable: Bool

    static func make(
        itemCount: Int,
        availableWidth: CGFloat,
        metrics: SpaceStripMetrics
    ) -> Self {
        guard itemCount > 0 else {
            return Self(
                slotFrames: [],
                slotWidth: metrics.slotSize,
                contentWidth: max(availableWidth, 0),
                displayMode: .regular,
                isScrollable: false
            )
        }

        let gapCount = CGFloat(itemCount - 1)
        guard availableWidth > 0 else {
            // Not measured yet: lay out at full size so the first frame does
            // not flash the compact treatment.
            return frames(
                itemCount: itemCount,
                slotWidth: metrics.slotSize,
                spacing: metrics.minSpacing,
                availableWidth: 0,
                displayMode: .regular,
                metrics: metrics
            )
        }

        // Stage 1: full-size slots with flexible spacing.
        let fullSpacing = gapCount > 0
            ? (availableWidth - CGFloat(itemCount) * metrics.slotSize) / gapCount
            : 0
        if gapCount == 0 || fullSpacing >= metrics.minSpacing {
            return frames(
                itemCount: itemCount,
                slotWidth: metrics.slotSize,
                spacing: min(max(fullSpacing, metrics.minSpacing), metrics.maxSpacing),
                availableWidth: availableWidth,
                displayMode: .regular,
                metrics: metrics
            )
        }

        // Stage 2: shrink slots (down to `minSlotSize`) at minimum spacing.
        let shrunkSlotWidth = (availableWidth - metrics.minSpacing * gapCount) / CGFloat(itemCount)
        if shrunkSlotWidth >= metrics.minSlotSize {
            return frames(
                itemCount: itemCount,
                slotWidth: shrunkSlotWidth,
                spacing: metrics.minSpacing,
                availableWidth: availableWidth,
                displayMode: .regular,
                metrics: metrics
            )
        }

        // Stage 3: compact dots at minimum slot width, no gaps; strip scrolls.
        return frames(
            itemCount: itemCount,
            slotWidth: metrics.minSlotSize,
            spacing: 0,
            availableWidth: availableWidth,
            displayMode: .compactDots,
            metrics: metrics
        )
    }

    func frame(at index: Int) -> CGRect? {
        guard slotFrames.indices.contains(index) else { return nil }
        return slotFrames[index]
    }

    private static func frames(
        itemCount: Int,
        slotWidth: CGFloat,
        spacing: CGFloat,
        availableWidth: CGFloat,
        displayMode: SpaceStripDisplayMode,
        metrics: SpaceStripMetrics
    ) -> Self {
        let slotsExtent = CGFloat(itemCount) * slotWidth
            + CGFloat(max(itemCount - 1, 0)) * spacing
        let originX = max((availableWidth - slotsExtent) / 2, 0)
        let slotFrames = (0..<itemCount).map { index in
            CGRect(
                x: originX + CGFloat(index) * (slotWidth + spacing),
                y: 0,
                width: slotWidth,
                height: metrics.slotSize
            )
        }
        return Self(
            slotFrames: slotFrames,
            slotWidth: slotWidth,
            contentWidth: max(slotsExtent, availableWidth),
            displayMode: displayMode,
            isScrollable: availableWidth > 0 && slotsExtent > availableWidth + 0.5
        )
    }
}

/// Port of Zen's `scrollIntoView({inline: "nearest"})` with `scroll-margin`:
/// the minimal offset change that makes a slot fully visible with `margin` of
/// breathing room on the scrolled-to side.
enum SpaceStripScrollPolicy {
    /// Returns the content offset the strip should scroll to so the slot at
    /// `slotIndex` is revealed, or `nil` when no scroll is needed.
    static func targetOffset(
        toReveal slotIndex: Int,
        geometry: SpaceStripGeometry,
        currentOffset: CGFloat,
        viewportWidth: CGFloat,
        margin: CGFloat
    ) -> CGFloat? {
        guard viewportWidth > 0, let slot = geometry.frame(at: slotIndex) else {
            return nil
        }

        let maxOffset = max(geometry.contentWidth - viewportWidth, 0)
        var target = currentOffset
        if maxOffset == 0 {
            target = 0
        } else if slot.minX - margin < target {
            target = slot.minX - margin
        } else if slot.maxX + margin > target + viewportWidth {
            target = slot.maxX + margin - viewportWidth
        }

        target = min(max(target, 0), maxOffset)
        return abs(target - currentOffset) > 0.5 ? target : nil
    }
}

struct SpaceStripLayout: Layout {
    let geometry: SpaceStripGeometry
    let metrics: SpaceStripMetrics

    func sizeThatFits(
        proposal _: ProposedViewSize,
        subviews _: Subviews,
        cache _: inout ()
    ) -> CGSize {
        CGSize(width: geometry.contentWidth, height: metrics.slotSize)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
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
