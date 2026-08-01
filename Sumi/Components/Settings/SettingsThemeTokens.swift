//
//  SettingsThemeTokens.swift
//  Sumi
//

import SwiftUI

enum SettingsThemeTokens {
    enum Colors {
        static var groupedBackground: Color {
            Color.primary.opacity(0.045)
        }

        static var fieldBackground: Color {
            Color.primary.opacity(0.055)
        }

        static var separator: Color {
            Color.primary.opacity(0.08)
        }

        static var stroke: Color {
            Color.clear
        }

        static var selectedNavigationBackground: Color {
            Color.accentColor
        }

        static var selectedNavigationForeground: Color {
            Color.white
        }

        static var compactSelectedNavigationBackground: Color {
            Color.accentColor.opacity(0.16)
        }

        static var paneIconForeground: Color {
            Color.white
        }

        static var paneIconShadow: Color {
            Color.black.opacity(0.14)
        }

        static var floatingRowShadow: Color {
            Color.black.opacity(0.16)
        }

        static var warningText: Color {
            Color.red
        }

        static var warningBackground: Color {
            Color.red.opacity(0.10)
        }

        static var warningBorder: Color {
            Color.red.opacity(0.35)
        }
    }

    enum Typography {
        static let searchIcon = Font.system(size: 15, weight: .medium)
        static let searchField = Font.system(size: 14)
        static let sidebarSectionHeader = Font.system(size: 11, weight: .semibold)
        static let emptyStateIcon = Font.system(size: 26, weight: .medium)
        static let searchEngineActionIcon = Font.system(size: 13, weight: .regular)
        static let protectionWarningIcon = Font.system(size: 14, weight: .semibold)
        static let profileNameField = Font.system(size: 15)
        static let profileRowActionIcon = Font.system(size: 14, weight: .regular)

        static func sidebarRowTitle(isSelected: Bool) -> Font {
            .system(size: 14, weight: isSelected ? .semibold : .regular)
        }

        static func paneIcon(size: CGFloat) -> Font {
            .system(size: size, weight: .semibold)
        }
    }
}
