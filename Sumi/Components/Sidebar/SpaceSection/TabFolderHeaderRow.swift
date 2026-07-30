//
//  TabFolderHeaderRow.swift
//  Sumi
//

import SwiftUI

struct TabFolderHeaderRow: View {
    let title: String
    let glyphPresentation: SumiFolderGlyphPresentationState
    let glyphPalette: SumiFolderGlyphPalette
    let isInteractive: Bool
    /// Zen parity: collapsed folders with sticky rows offer an unload/reset
    /// affordance on hover. Nil hides the affordance entirely.
    var onResetProjection: (() -> Void)?
    var resetProjectionErrorTitle: String?

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @State private var isHovered = false
    @State private var isResetHovered = false

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var displayIsHovering: Bool {
        isHovered
    }

    var body: some View {
        HStack(spacing: 0) {
            iconSlot
            titleView
            Spacer(minLength: 0)
            if let onResetProjection {
                resetProjectionButton(action: onResetProjection)
            }
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .geometryGroup()
        .sidebarRowSurface(
            background: displayIsHovering ? tokens.sidebarRowHover : Color.clear,
            cornerRadius: sumiSettings.resolvedCornerRadius(12),
            tokens: tokens,
            isVisible: displayIsHovering,
            drawsSelectionShadow: false
        )
        .contentShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
        .sidebarHover($isHovered, isEnabled: isInteractive)
    }

    private func resetProjectionButton(action: @escaping () -> Void) -> some View {
        let showsButton = displayIsHovering && isInteractive
        return Button(action: action) {
            Image(systemName: resetProjectionErrorTitle == nil ? "minus" : "arrow.clockwise")
                .font(SidebarThemeTokens.Typography.trailingAction)
                .foregroundColor(tokens.primaryText)
                .frame(
                    width: SidebarRowLayout.trailingActionSize,
                    height: SidebarRowLayout.trailingActionSize
                )
                .background(isResetHovered ? tokens.fieldBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(SidebarZenActionButtonStyle(isEnabled: showsButton))
        .opacity(showsButton ? 1 : 0)
        .allowsHitTesting(showsButton)
        .accessibilityHidden(!showsButton)
        .accessibilityLabel(resetProjectionErrorTitle ?? "Unload folder tabs")
        .help(resetProjectionErrorTitle ?? "Unload tabs and collapse")
        .sidebarHover($isResetHovered, isEnabled: showsButton)
        .sidebarAppKitPrimaryAction(
            isEnabled: showsButton,
            isInteractionEnabled: isInteractive,
            action: action
        )
    }

    private var titleView: some View {
        SidebarRowTitleLabel(
            title: title,
            font: SidebarThemeTokens.Typography.folderTitle,
            color: tokens.primaryText
        )
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
