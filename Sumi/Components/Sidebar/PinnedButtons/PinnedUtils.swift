//
//  PinnedUtils.swift
//  Sumi
//
//

import SwiftUI

/// Fixed layout metrics for essential/pinned tiles. These never varied per
/// call site (the former `PinnedTabsConfiguration` enum had a single `.large`
/// case), so they live here as plain constants instead of being threaded as a
/// value through every tile, grid, snapshot, and drag-preview API.
enum PinnedTileMetrics {
    static let faviconHeight: CGFloat = 20
    static let minWidth: CGFloat = 47
    static let height: CGFloat = 47
    static let cornerRadius: CGFloat = 12
    static let strokeWidth: CGFloat = 2
    static let gridSpacing: CGFloat = 7

    /// Height the Essentials zone keeps when it holds no items and shows no
    /// placeholder: enough to stay a reachable drop target without reading as a
    /// gap in the sidebar. Shared by the live grid, its layout model, and the
    /// space-transition snapshot so all three collapse to the same height.
    static let collapsedEssentialsRevealHeight: CGFloat = 6
}
