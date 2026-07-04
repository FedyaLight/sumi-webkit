//
//  SumiScriptsUIThemeTokens.swift
//  Sumi
//
//  Visual tokens for the SumiScripts manager and page popover.
//

import AppKit
import SwiftUI

enum SumiScriptsUIStyle {
    static var panelRowBackground: Color { Color(NSColor.controlBackgroundColor) }
    static var versionBadgeBackground: Color { Color.accentColor.opacity(0.1) }
    static var footerButtonBackground: Color { Color.primary.opacity(0.05) }
    static var secondaryText: Color { .secondary }
    static var subtleSecondaryText: Color { .secondary.opacity(0.7) }
    static var emptyStateIcon: Color { .secondary.opacity(0.3) }
}

enum SumiScriptsUITypography {
    static var managerTitle: Font { .title2 }
    static var managerSubtitle: Font { .subheadline }
    static var sectionTitle: Font { .headline }
    static var sectionCaption: Font { .caption }
    static var sectionCaptionSmall: Font { .caption2 }
    static var runtimeMessage: Font { .system(size: 11, design: .monospaced) }
    static var runtimeStack: Font { .system(size: 10, design: .monospaced) }
    static var managerFilename: Font { .system(size: 10, design: .monospaced) }
    static var managerRowActions: Font { .title3 }
    static var infoBadge: Font { .system(size: 9) }

    static var popoverHeader: Font { .headline }
    static var popoverHeaderStatus: Font { .caption }
    static var popoverStateIcon: Font { .system(size: 32) }
    static var popoverStateTitle: Font { .subheadline }
    static var popoverStateCaption: Font { .caption }
    static var popoverSectionHeader: Font { .system(size: 10, weight: .bold) }
    static var popoverScriptTitle: Font { .system(size: 13, weight: .medium) }
    static var popoverScriptVersion: Font { .system(size: 10) }
    static var popoverDisabledHint: Font { .system(size: 9) }
    static var popoverCommandTitle: Font { .system(size: 12) }
    static var popoverCommandChevron: Font { .system(size: 10) }
}
