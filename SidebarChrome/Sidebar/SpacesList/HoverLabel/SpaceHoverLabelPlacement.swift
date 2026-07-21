//
//  SpaceHoverLabelPlacement.swift
//  Sumi
//
//  Where the hover label sits above the spaces strip. Pure geometry, like its
//  neighbour `SpaceStripScrollPolicy`.
//

import SwiftUI

struct SpaceHoverLabelAnchor {
    let label: SpaceHoverLabel
    let bounds: Anchor<CGRect>
}

struct SpaceHoverLabelAnchorPreference: PreferenceKey {
    static let defaultValue: SpaceHoverLabelAnchor? = nil

    static func reduce(
        value: inout SpaceHoverLabelAnchor?,
        nextValue: () -> SpaceHoverLabelAnchor?
    ) {
        value = nextValue() ?? value
    }
}

enum SpaceHoverLabelPlacement {
    /// Vertical gap between the label's bottom edge and the strip's top edge.
    static let verticalOffset: CGFloat = 6

    /// Centres the plate on its resolved icon anchor and only gives way when a
    /// container edge requires it. All scroll and strip offsets have already
    /// been resolved by SwiftUI's anchor system before this seam is crossed.
    static func centerX(
        anchorX: CGFloat,
        containerWidth: CGFloat,
        labelWidth: CGFloat
    ) -> CGFloat {
        let halfWidth = labelWidth / 2
        let firstFittingCenter = halfWidth
        let lastFittingCenter = max(containerWidth - halfWidth, firstFittingCenter)
        return min(max(anchorX, firstFittingCenter), lastFittingCenter)
    }
}
