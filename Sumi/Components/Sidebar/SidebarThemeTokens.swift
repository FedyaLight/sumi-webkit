//
//  SidebarThemeTokens.swift
//  Sumi
//

import AppKit
import SwiftUI

enum SidebarThemeTokens {
    enum Colors {
        static let collapsedSidebarShadow = NSColor.black

        /// A SwiftUI mask composites by luminance, so a fully-shown region is
        /// pure white in every theme. This is a mask channel value, not a
        /// palette colour, and must not follow the workspace theme.
        static let opaqueMask = Color.white

        static func collapsedSidebarTransitionOverlay(isNativeSurfaceLight: Bool) -> Color {
            isNativeSurfaceLight ? Color.black : Color.white
        }
    }

    enum Typography {
        static let extensionActionBadge = Font.system(size: 8, weight: .bold, design: .rounded)
        static let extensionActionFallbackIcon = Font.system(size: 16, weight: .medium)
        static let folderTitle = Font.system(size: 14, weight: .semibold)
        static let rowTitle = Font.system(size: 13, weight: .medium)
        static let rowAccessory = Font.system(size: 12, weight: .medium)
        static let trailingAction = Font.system(size: 12, weight: .heavy)
        /// Zen parity: the in-list New-Tab row carries the same type as folder
        /// titles (in Zen every sidebar row inherits one font-size and the
        /// new-tab button is weighted up, not down, relative to tab rows).
        static let newTabRow = folderTitle
        static let pinnedTileAction = Font.system(size: 11, weight: .bold)
        static let essentialsPlaceholderTitle = Font.system(size: 14, weight: .semibold)
        static let essentialsPlaceholderSubtitle = Font.system(size: 12, weight: .medium)
        static let essentialsPlaceholderDismiss = Font.system(size: 10, weight: .semibold)

        static func chromeTemplateIcon(size: CGFloat) -> Font {
            .system(size: size * 0.78, weight: .medium)
        }

        static func launcherEmoji(size: CGFloat) -> Font {
            .system(size: size * 0.75)
        }

        static func pinnedTileGlyphText(size: CGFloat) -> Font {
            .system(size: size * 0.72)
        }

        /// Collapsed-folder hover preview. The panel is denser than the sidebar
        /// list it hovers over, so it carries its own scale rather than
        /// inheriting the row tokens above.
        enum FolderPreview {
            static let searchFieldIcon = Font.system(size: 12, weight: .medium)
            static let emptyState = Font.system(size: 12, weight: .medium)
            static let rowTitle = Font.system(size: 13, weight: .regular)
            static let rowSecondaryText = Font.system(size: 10, weight: .medium)

            static func rowGlyphText(iconSize: CGFloat) -> Font {
                .system(size: iconSize - 2)
            }

            static func rowTemplateIcon(iconSize: CGFloat) -> Font {
                .system(size: iconSize - 3, weight: .medium)
            }
        }
    }
}
