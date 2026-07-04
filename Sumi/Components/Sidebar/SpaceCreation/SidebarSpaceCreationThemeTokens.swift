import SwiftUI

enum SidebarSpaceCreationThemeTokens {
    enum Typography {
        static let titleIcon = Font.system(size: SidebarRowLayout.faviconSize * 0.78, weight: .semibold)
        static let title = Font.system(size: 14, weight: .semibold)
        static let field = Font.system(size: 14, weight: .medium)
        static let rowLabel = Font.system(size: 13, weight: .medium)
        static let profileMenuIcon = Font.system(size: 13, weight: .medium)
        static let profileMenuText = Font.system(size: 13, weight: .medium)
        static let profileMenuChevron = Font.system(size: 9, weight: .semibold)
        static let primaryButton = Font.system(size: 13, weight: .semibold)
        static let secondaryButton = Font.system(size: 13, weight: .medium)
        static let spaceEmoji = Font.system(size: 18)
        static let spaceSymbol = Font.system(size: 16, weight: .medium)
        static let profileIcon = Font.system(size: 17, weight: .medium)
        static let validation = Font.system(size: 11, weight: .medium)
    }

    enum Colors {
        static let validationText = Color.red
    }
}
