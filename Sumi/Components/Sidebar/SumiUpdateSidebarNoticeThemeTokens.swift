import SwiftUI

enum SumiUpdateSidebarNoticeThemeTokens {
    enum Typography {
        static let availableTitle = Font.system(size: 12, weight: .regular)
        static let availableAction = Font.system(size: 12, weight: .medium)
        static let compactIcon = Font.system(size: 17, weight: .semibold)
    }

    enum Colors {
        static func availablePillBackground(tokens: ChromeThemeTokens?) -> Color {
            if let tokens {
                return tokens.sidebarRowHover.opacity(0.55)
            }
            return Color.primary.opacity(0.05)
        }

        static func availablePillBorder(tokens: ChromeThemeTokens?) -> Color {
            tokens?.separator ?? Color.primary.opacity(0.10)
        }

        static func availableCardBackground(tokens: ChromeThemeTokens?) -> Color {
            tokens?.floatingSurfaceBackground ?? Color(nsColor: .controlBackgroundColor)
        }

        static func availableCardBorder(tokens: ChromeThemeTokens?) -> Color {
            tokens?.floatingSurfaceBorder ?? Color.primary.opacity(0.14)
        }

        static func availableActionBackground(tokens: ChromeThemeTokens?) -> Color {
            tokens?.buttonPrimaryBackground ?? .accentColor
        }

        static func availableActionForeground(tokens: ChromeThemeTokens?) -> Color {
            tokens?.buttonPrimaryText ?? .white
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

    }
}
