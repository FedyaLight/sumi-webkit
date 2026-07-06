//
//  SpaceStripLayout.swift
//  Sumi
//
//  Deterministic slot geometry + layout for the sidebar spaces strip. The
//  drag-to-reorder state machine itself is the shared `ReorderDragState`.
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

    static func make(
        itemCount: Int,
        availableWidth: CGFloat,
        metrics: SpaceStripMetrics
    ) -> Self {
        guard itemCount > 0 else {
            return Self(slotFrames: [])
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

        return Self(slotFrames: frames)
    }

    func frame(at index: Int) -> CGRect? {
        guard slotFrames.indices.contains(index) else { return nil }
        return slotFrames[index]
    }
}

struct SpaceStripLayout: Layout {
    let metrics: SpaceStripMetrics

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
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
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
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
