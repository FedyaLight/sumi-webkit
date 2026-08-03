import SwiftUI

enum SumiUpdateSidebarNoticeThemeTokens {
    enum Typography {
        static let availableTitle = Font.system(size: 12, weight: .regular)
        static let availableAction = Font.system(size: 12, weight: .medium)
        static let completedHeading = Font.system(size: 12, weight: .medium)
        static let completedLink = Font.system(size: 12, weight: .regular)
        static let completedIcon = Font.system(size: 16, weight: .regular)
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

        static func completedCardBackground(tokens: ChromeThemeTokens?) -> Color {
            tokens?.floatingSurfaceBackground ?? Color(nsColor: .controlBackgroundColor)
        }

        static func completedCardBorder(tokens: ChromeThemeTokens?) -> Color {
            tokens?.floatingSurfaceBorder ?? Color.primary.opacity(0.14)
        }

        static func completedSeparator(tokens: ChromeThemeTokens?) -> Color {
            tokens?.separator ?? Color.primary.opacity(0.10)
        }

        static func completedHeadingForeground(tokens: ChromeThemeTokens?) -> Color {
            tokens?.primaryText ?? .primary
        }

        static func completedCloseForeground(tokens: ChromeThemeTokens?) -> Color {
            tokens?.secondaryText ?? .secondary
        }

        static let completedAccent = Color(
            .sRGB,
            red: 156.0 / 255.0,
            green: 116.0 / 255.0,
            blue: 101.0 / 255.0,
            opacity: 1
        )

        static func completedNeutralForeground(tokens: ChromeThemeTokens?) -> Color {
            tokens?.secondaryText ?? .secondary
        }

        static func completedRowHover(tokens: ChromeThemeTokens?) -> Color {
            tokens?.floatingSurfaceHover ?? Color.primary.opacity(0.06)
        }

    }
}
