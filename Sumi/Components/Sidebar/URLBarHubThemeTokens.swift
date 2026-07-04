//
//  URLBarHubThemeTokens.swift
//  Sumi
//
//  Typography and local visual tokens for URL bar hub detail panes.
//

import SwiftUI

enum URLBarHubTypography {
    static var detailHeaderTitle: Font { .system(size: 15, weight: .semibold) }
    static var detailHeaderSubtitle: Font { .system(size: 12, weight: .medium) }
    static var introTitle: Font { .system(size: 18, weight: .semibold) }
    static var introBody: Font { .system(size: 13) }
    static var sectionTitle: Font { .system(size: 13, weight: .semibold) }
    static var sectionHeaderTitle: Font { .system(size: 12, weight: .semibold) }
    static var sectionHeaderAction: Font { .system(size: 11, weight: .semibold) }
    static var secondaryRowText: Font { .system(size: 12) }
    static var emptyRowText: Font { .system(size: 12.5) }
    static var deleteIcon: Font { .system(size: 18, weight: .semibold) }
    static var confirmationTitle: Font { .system(size: 16, weight: .semibold) }
    static var confirmationButton: Font { .system(size: 13.5, weight: .semibold) }
    static var rowIcon: Font { .system(size: 13, weight: .semibold) }
    static var entryTitle: Font { .system(size: 13, weight: .medium) }
    static var entrySummary: Font { .system(size: 11.5) }
    static var actionIcon: Font { .system(size: 11.5, weight: .semibold) }
    static var actionTitle: Font { .system(size: 11.5, weight: .medium) }
    static var faviconFallback: Font { .system(size: 17, weight: .medium) }
    static var iconButton: Font { .system(size: 15, weight: .semibold) }
    static var footerStatusTitle: Font { .system(size: 13, weight: .semibold) }
    static var protectionIcon: Font { .system(size: 17, weight: .medium) }
    static var protectionTitle: Font { .system(size: 13, weight: .medium) }
    static var protectionSecondary: Font { .system(size: 11.5) }
    static var protectionError: Font { .system(size: 11.5, weight: .medium) }
    static var permissionHint: Font { .system(size: 11.5) }
    static var permissionHeaderTitle: Font { .system(size: 13, weight: .semibold) }
    static var permissionHeaderSubtitle: Font { .system(size: 11.5) }
    static var permissionFooterButton: Font { .system(size: 12.5, weight: .medium) }
    static var permissionBadge: Font { .system(size: 7, weight: .bold) }
    static var ruleEditor: Font { .system(size: 12, design: .monospaced) }
    static var bookmarkError: Font { .system(size: 11.5, weight: .medium) }
    static var bookmarkEditorError: Font { .system(size: 12, weight: .medium) }
    static var bookmarkEditorTitle: Font { .system(size: 18, weight: .semibold) }
    static var bookmarkEditorSubtitle: Font { .system(size: 12.5, weight: .medium) }
    static var bookmarkEditorFieldLabel: Font { .system(size: 12, weight: .semibold) }
    static var bookmarkEditorFolderIcon: Font { .system(size: 13.5, weight: .semibold) }
    static var bookmarkEditorFolderTitle: Font { .system(size: 13.5, weight: .semibold) }
    static var bookmarkEditorFolderChevron: Font { .system(size: 11, weight: .semibold) }
    static var bookmarkEditorTextField: Font { .system(size: 13.5) }
    static var bookmarkEditorFooterButton: Font { .system(size: 13, weight: .semibold) }
}

enum URLBarHubOverlayStyle {
    static func deleteBackdrop(for colorScheme: ColorScheme) -> Color {
        Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12)
    }

    static func deleteShadow(for colorScheme: ColorScheme) -> Color {
        Color.black.opacity(colorScheme == .dark ? 0.45 : 0.18)
    }

    static var destructiveIconForeground: Color { .white }
    static var protectionErrorText: Color { Color.red.opacity(0.9) }
    static var bookmarkErrorText: Color { Color.red.opacity(0.9) }
    static var transparent: Color { .clear }
}
