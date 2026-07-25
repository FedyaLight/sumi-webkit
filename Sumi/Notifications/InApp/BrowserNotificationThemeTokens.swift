//
//  BrowserNotificationThemeTokens.swift
//  Sumi
//

import SwiftUI

/// Type scale for the in-app notification toast. The toast floats over page
/// content at a fixed compact size, so it carries its own tokens rather than
/// inheriting the sidebar or chrome scales.
enum BrowserNotificationThemeTokens {
    enum Typography {
        static let leadingIcon = Font.system(size: 14, weight: .semibold)
        static let title = Font.system(size: 13, weight: .semibold)
        static let subtitle = Font.system(size: 11)
        static let actionIcon = Font.system(size: 11, weight: .semibold)
        static let actionLabel = Font.system(
            size: 11,
            weight: .medium,
            design: .monospaced
        )
    }

    enum Colors {
        /// Interaction ramp for a toast action button. The toast already sits
        /// on a material, so the ramp tints with the foreground colour rather
        /// than painting an opaque fill.
        enum ActionBackground {
            static let pressed = Color.primary.opacity(0.12)
            static let hovered = Color.primary.opacity(0.08)
            static let rest = Color.primary.opacity(0.04)
        }
    }
}
