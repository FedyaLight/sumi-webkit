import SwiftUI
import SumiDomain

enum SumiPermissionRuntimeControlsThemeTokens {
    enum Typography {
        static let result = Font.system(size: 11.5, weight: .medium)
        static let rowTitle = Font.system(size: 13, weight: .semibold)
        static let rowSubtitle = Font.system(size: 11.5)
        static let disabledReason = Font.system(size: 11.5, weight: .medium)
        static let actionButton = Font.system(size: 11.5, weight: .medium)
        static let promptTitle = Font.system(size: 15, weight: .semibold)
        static let promptCloseIcon = Font.system(size: 11, weight: .semibold)
        static let promptDeviceIcon = Font.system(size: 12, weight: .medium)
        static let promptDeviceText = Font.system(size: 12)
        static let promptSystemIcon = Font.system(size: 18, weight: .semibold)
        static let promptSystemTitle = Font.system(size: 14, weight: .semibold)
        static let promptSystemMessage = Font.system(size: 12)

        static func promptButton(isPrimary: Bool) -> Font {
            Font.system(size: 13, weight: isPrimary ? .semibold : .medium)
        }
    }

    enum DestructiveColors {
        static let result = Color.red.opacity(0.9)
        static let foreground = Color.red.opacity(0.88)
        static let pressedBackground = Color.red.opacity(0.16)
        static let hoveredBackground = Color.red.opacity(0.12)

        static func promptForeground(isEnabled: Bool) -> Color {
            Color.red.opacity(isEnabled ? 0.95 : 0.55)
        }

        static let promptPressedBackground = Color.red.opacity(0.18)
        static let promptHoveredBackground = Color.red.opacity(0.12)
    }

    enum SiteSettingsColors {
        static let searchFieldBackground = Color.secondary.opacity(0.08)
        static let searchFieldBorder = Color.secondary.opacity(0.18)
    }
}
