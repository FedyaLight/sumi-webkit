//
//  OverlayScrollIndicatorStyle.swift
//  Sumi
//

import AppKit

/// Shared visual tokens for AppKit overlay scroll indicators (sidebar + web content).
enum OverlayScrollIndicatorStyle {
    static let thumbWidth: CGFloat = 3
    static let expandedThumbWidth: CGFloat = 7
    static let trackWidth: CGFloat = 12
    static let thumbOpacity: CGFloat = 0.40
    static let minimumThumbHeight: CGFloat = 28
    static let thumbLayoutAnimationDuration: TimeInterval = 0.12
    static let visibleDuration: TimeInterval = 2.0
    static let fadeDuration: TimeInterval = 0.18
    /// Keeps the expanded thumb a few points inside the trailing edge.
    static let edgeInset: CGFloat = 3

    /// Mid-gray that reads on both light and dark page/chrome backgrounds.
    /// Opacity is applied by the indicator view (`thumbOpacity`), not baked in.
    static let thumbColor = NSColor(srgbRed: 0.50, green: 0.50, blue: 0.50, alpha: 1.0)
}
