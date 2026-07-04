//
//  SidebarThemeTokens.swift
//  Sumi
//

import AppKit
import SwiftUI

enum SidebarThemeTokens {
    enum Typography {
        static let extensionActionBadge = Font.system(size: 8, weight: .bold, design: .rounded)
        static let extensionActionFallbackIcon = Font.system(size: 16, weight: .medium)
        static let folderTitle = Font.system(size: 14, weight: .semibold)
        static let rowTitle = Font.system(size: 13, weight: .medium)
        static var rowTitleNSFont: NSFont {
            NSFont.systemFont(ofSize: 13, weight: .medium)
        }
        static let rowAccessory = Font.system(size: 12, weight: .medium)
        static let trailingAction = Font.system(size: 12, weight: .heavy)
        static let newTabRow = Font.system(size: 13, weight: .regular)
        static let pinnedTileAction = Font.system(size: 11, weight: .bold)

        static func chromeTemplateIcon(size: CGFloat) -> Font {
            .system(size: size * 0.78, weight: .medium)
        }

        static func launcherEmoji(size: CGFloat) -> Font {
            .system(size: size * 0.75)
        }

        static func pinnedTileGlyphText(size: CGFloat) -> Font {
            .system(size: size * 0.72)
        }
    }
}
