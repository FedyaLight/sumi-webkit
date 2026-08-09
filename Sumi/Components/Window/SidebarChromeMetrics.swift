import SwiftUI

enum SidebarChromeMetrics {
    static let controlLeadingPadding: CGFloat = 18
    static let contentHorizontalPadding: CGFloat = ChromeLayoutTokens.sidebarContentHorizontalPadding
    static let topControlInset: CGFloat = 0
    static let controlStripHeight: CGFloat = 40
    static let controlToURLBarSpacing: CGFloat = 4
    static let urlBarToSpaceTitleSpacing: CGFloat = 4
    static let favoriteToSpaceTitleSpacing: CGFloat = 8
    static let controlSpacing: CGFloat = 0
    static let navigationButtonSize: CGFloat = 30
    static let navigationIconSize: CGFloat = 14

    static func favoriteTopPadding(
        showsFavoriteSurface: Bool,
        showsExtensionGrid: Bool
    ) -> CGFloat {
        guard showsFavoriteSurface, !showsExtensionGrid else { return 0 }
        return max(
            favoriteToSpaceTitleSpacing - urlBarToSpaceTitleSpacing,
            0
        )
    }
}
