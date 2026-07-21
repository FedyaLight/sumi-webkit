import CoreGraphics

/// Zen-parity metrics for the collapsed-folder hover preview panel.
///
/// Mirrors `#zen-folder-tabs-popup` in Zen's `zen-folders.css`: a 250pt panel
/// whose search header is separated by a hairline, over 48pt row slots (40pt of
/// content plus 4pt gutters top and bottom).
enum SidebarFolderPreviewMetrics {
    static let width: CGFloat = 250
    /// 16pt glass icon with Zen's 10pt vertical margins inside 6pt header padding.
    static let searchHeaderHeight: CGFloat = 48
    static let separatorHeight: CGFloat = 1
    static let searchIconSize: CGFloat = 16
    static let searchIconLeading: CGFloat = 10
    static let searchIconTrailing: CGFloat = 2
    static let headerPadding: CGFloat = 6

    static let rowContentHeight: CGFloat = 40
    static let rowVerticalGutter: CGFloat = 4
    /// Zen positions the panel in whole row slots, gutters included.
    static let rowSlotHeight: CGFloat = rowContentHeight + rowVerticalGutter * 2
    static let rowCornerRadius: CGFloat = 6
    static let rowIconSize: CGFloat = 16
    static let rowIconLeading: CGFloat = 4
    static let rowIconTrailing: CGFloat = 10

    static let listHorizontalPadding: CGFloat = 4
    static let maxListHeight: CGFloat = 263
    /// Zen clamps its placement math at six slots even though the list scrolls further.
    static let placementRowCap = 6

    /// Panel height for a candidate count. Derived from the unfiltered count so
    /// the panel does not resize under the pointer while the query narrows.
    static func panelHeight(candidateCount: Int) -> CGFloat {
        let listHeight = min(
            CGFloat(max(candidateCount, 1)) * rowSlotHeight,
            maxListHeight
        )
        return searchHeaderHeight + separatorHeight + listHeight
    }

    static func panelSize(candidateCount: Int) -> CGSize {
        CGSize(width: width, height: panelHeight(candidateCount: candidateCount))
    }
}

/// Pure placement math for the folder hover preview.
///
/// Ports Zen's `#searchPopupOptions` (`ZenFolders.mjs`): the panel's leading top
/// corner is pinned to the folder header's trailing top corner, pushed 10pt
/// outward and lifted by half the visible list so it reads as centred on the
/// row. Zen relies on the widget toolkit to keep the panel on screen; an
/// in-window overlay has to clamp itself, which is what `containerBounds` does.
enum SidebarFolderPreviewPlacement {
    static let anchorGap: CGFloat = 10
    static let containerMargin: CGFloat = 8

    /// - Parameters:
    ///   - anchorRect: folder header frame in the window's SwiftUI-global space.
    ///   - containerBounds: the window chrome bounds in the same space.
    static func origin(
        anchorRect: CGRect,
        panelSize: CGSize,
        candidateCount: Int,
        sidebarPosition: SidebarPosition,
        containerBounds: CGRect
    ) -> CGPoint {
        let liftedSlots = min(max(candidateCount, 1), SidebarFolderPreviewMetrics.placementRowCap)
        let lift = CGFloat(liftedSlots) * SidebarFolderPreviewMetrics.rowSlotHeight / 2

        let unclampedX: CGFloat
        switch sidebarPosition {
        case .left:
            unclampedX = anchorRect.maxX + anchorGap
        case .right:
            unclampedX = anchorRect.minX - anchorGap - panelSize.width
        }
        let unclampedY = anchorRect.minY - lift

        return CGPoint(
            x: clamp(
                unclampedX,
                lowerBound: containerBounds.minX + containerMargin,
                upperBound: containerBounds.maxX - containerMargin - panelSize.width
            ),
            y: clamp(
                unclampedY,
                lowerBound: containerBounds.minY + containerMargin,
                upperBound: containerBounds.maxY - containerMargin - panelSize.height
            )
        )
    }

    static func frame(
        anchorRect: CGRect,
        candidateCount: Int,
        sidebarPosition: SidebarPosition,
        containerBounds: CGRect
    ) -> CGRect {
        let size = SidebarFolderPreviewMetrics.panelSize(candidateCount: candidateCount)
        return CGRect(
            origin: origin(
                anchorRect: anchorRect,
                panelSize: size,
                candidateCount: candidateCount,
                sidebarPosition: sidebarPosition,
                containerBounds: containerBounds
            ),
            size: size
        )
    }

    /// A container smaller than the panel would invert the clamp bounds; pin to
    /// the leading edge instead of letting the upper bound win.
    private static func clamp(
        _ value: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        guard upperBound > lowerBound else { return lowerBound }
        return min(max(value, lowerBound), upperBound)
    }
}
