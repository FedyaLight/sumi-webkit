//
//  TabFolderHeaderRow.swift
//  Sumi
//

import SwiftUI

struct TabFolderHeaderRow: View {
    let title: String
    let glyphPresentation: SumiFolderGlyphPresentationState
    let glyphPalette: SumiFolderGlyphPalette
    let isDropHighlighted: Bool
    let isInteractive: Bool
    var dropHighlightHorizontalBleed: CGFloat = 8

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(
            isHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            iconSlot
            titleView
            Spacer(minLength: 0)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .geometryGroup()
        .background(alignment: .center) {
            if isDropHighlighted {
                RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous)
                    .fill(tokens.sidebarRowHover)
                    .padding(.horizontal, -dropHighlightHorizontalBleed)
            }
        }
        .sidebarRowSurface(
            background: displayIsHovering ? tokens.sidebarRowHover : Color.clear,
            cornerRadius: sumiSettings.resolvedCornerRadius(12),
            tokens: tokens,
            isVisible: displayIsHovering,
            drawsSelectionShadow: false
        )
        .contentShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
        .sidebarDDGHover($isHovered, isEnabled: isInteractive)
    }

    private var titleView: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tokens.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var iconView: some View {
        SumiFolderGlyphView(
            presentation: glyphPresentation,
            palette: glyphPalette
        )
        .frame(
            width: SidebarRowLayout.folderGlyphSize,
            height: SidebarRowLayout.folderGlyphSize,
            alignment: .center
        )
    }

    /// Full-size Zen glyph; horizontal center matches favicon column, layout width matches tab rows (`folderTitleLeading`).
    private var iconSlot: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: SidebarRowLayout.folderTitleLeading, height: SidebarRowLayout.rowHeight)
            iconView
                .offset(x: SidebarRowLayout.folderHeaderGlyphCenteringOffset)
        }
        .frame(width: SidebarRowLayout.folderTitleLeading, alignment: .leading)
    }
}
