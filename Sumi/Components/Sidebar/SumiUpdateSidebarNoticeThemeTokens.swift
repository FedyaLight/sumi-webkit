import SwiftUI

enum SumiUpdateSidebarNoticeThemeTokens {
    enum Typography {
        static let title = Font.system(size: 13, weight: .semibold)
        static let detail = Font.system(size: 12)
        static let statusIcon = Font.system(size: 15, weight: .semibold)
        static let dismissIcon = Font.system(size: 11, weight: .bold)
        static let compactIcon = Font.system(size: 17, weight: .semibold)
    }

    enum Colors {
        static func cardBackground(isHovering: Bool) -> Color {
            Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.94 : 0.86)
        }

        static func cardBorder(isHovering: Bool) -> Color {
            Color.primary.opacity(isHovering ? 0.18 : 0.12)
        }

        static func cardShadow(isHovering: Bool) -> Color {
            Color.black.opacity(isHovering ? 0.10 : 0.06)
        }

        static func symbol(for visualStyle: SumiUpdateSidebarNoticeVisualStyle) -> Color {
            switch visualStyle {
            case .accent, .progress:
                return .accentColor
            case .success:
                return .green
            case .warning:
                return .yellow
            }
        }

        static func dismissForeground(isHovering: Bool) -> Color {
            Color.primary.opacity(isHovering ? 0.86 : 0.68)
        }

        static func dismissBackground(isHovering: Bool) -> Color {
            Color.primary.opacity(isHovering ? 0.12 : 0.075)
        }

        static func dismissBorder(isHovering: Bool) -> Color {
            Color.primary.opacity(isHovering ? 0.16 : 0.10)
        }
    }
}
