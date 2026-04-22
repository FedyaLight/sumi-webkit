//
//  SidebarRowLayout.swift
//  Sumi
//

import CoreGraphics

enum SidebarRowLayout {
    static let rowHeight: CGFloat = 36
    static let faviconSize: CGFloat = 18
    static let leadingInset: CGFloat = 12
    static let iconTrailingSpacing: CGFloat = 8
    static let trailingInset: CGFloat = 10
    static let folderGlyphSize: CGFloat = 28
    /// Centers the 28pt folder glyph on the 18pt favicon column (layout width before title stays `folderTitleLeading`).
    static let folderHeaderGlyphCenteringOffset: CGFloat = (faviconSize - folderGlyphSize) * 0.5
    /// Horizontal offset from row leading to folder title text (matches favicon column + gap before title).
    static let folderTitleLeading: CGFloat = faviconSize + iconTrailingSpacing
    static let changedLauncherResetWidth: CGFloat = 42
    static let changedLauncherTitleLeading: CGFloat = 4
    static let changedLauncherSeparatorWidth: CGFloat = 2.5
    static let changedLauncherSeparatorHeight: CGFloat = 14
    static let changedLauncherResetHeight: CGFloat = rowHeight
    static let changedLauncherResetIconLeading: CGFloat = 12
    static let changedLauncherResetTrailingGap: CGFloat = 4
}
