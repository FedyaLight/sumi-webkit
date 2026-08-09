//
//  PinnedUtils.swift
//  Sumi
//
//

import SwiftUI

/// Fixed layout metrics for favorite/pinned tiles. These never varied per
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

    /// Empty Favorite have no visual height. The drag hit policy widens their
    /// geometry independently, so the drop target remains reachable without
    /// leaving a gap before the Space title. Shared by the live grid, its layout
    /// model, and the space-transition snapshot.
    static let collapsedFavoriteRevealHeight: CGFloat = 0
}
