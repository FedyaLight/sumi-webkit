//
//  ShortcutSplitPlaceholderRow.swift
//  Sumi
//

import SwiftUI

struct ShortcutSplitPlaceholderRow: View {
    @ObservedObject var pin: ShortcutPin
    let isSelected: Bool
    let accessibilityID: String
    let isAppKitInteractionEnabled: Bool
    var onMiddleClick: () -> Void = {}
    let action: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @State private var isRowHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "rectangle.split.2x1")
                .font(SidebarThemeTokens.Typography.chromeTemplateIcon(size: SidebarRowLayout.faviconSize))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tokens.primaryText)
                .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.leading, SidebarRowLayout.leadingInset)
                .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)

            SumiTabTitleLabel(
                title: pin.preferredDisplayTitle,
                font: SidebarThemeTokens.Typography.rowTitleNSFont,
                textColor: tokens.primaryText,
                trailingPadding: 0,
                animated: false
            )
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarRowSurface(
            background: backgroundColor,
            cornerRadius: sumiSettings.resolvedCornerRadius(12),
            tokens: tokens,
            isVisible: drawsRowSurface,
            drawsSelectionShadow: isSelected
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .sidebarDDGHover($isRowHovered, isEnabled: isAppKitInteractionEnabled)
        .sidebarZenPressEffect(sourceID: accessibilityID, isEnabled: isAppKitInteractionEnabled)
        .sidebarAppKitPrimaryAction(
            isInteractionEnabled: isAppKitInteractionEnabled,
            sourceID: accessibilityID,
            onMiddleClick: onMiddleClick,
            action: action
        )
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue(isSelected ? "selected" : "split placeholder")
    }

    private var backgroundColor: Color {
        if isSelected {
            return tokens.sidebarRowActive
        }
        if displayIsHovering {
            return tokens.sidebarRowHover
        }
        return .clear
    }

    private var drawsRowSurface: Bool {
        isSelected || displayIsHovering
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(
            isRowHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }
}
