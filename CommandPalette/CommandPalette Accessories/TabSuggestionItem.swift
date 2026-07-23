//
//  TabSuggestionItem.swift
//  Sumi
//
//

import SwiftUI

struct TabSuggestionItem: View {
    @ObservedObject var tab: Tab
    var isSelected: Bool = false
    var selectedForeground: Color?
    var selectedChipBackground: Color?
    var selectedChipForeground: Color?

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        let tokens = themeContext.tokens(settings: sumiSettings)
        let foreground = isSelected ? (selectedForeground ?? tokens.primaryText) : tokens.secondaryText
        let chipBackground = isSelected ? (selectedChipBackground ?? tokens.commandPaletteChipBackground) : tokens.commandPaletteChipBackground
        let chipForeground = isSelected ? (selectedChipForeground ?? tokens.primaryText) : tokens.tertiaryText

        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 9) {
                CommandPaletteFaviconContainer {
                    tab.favicon
                        .foregroundStyle(foreground)
                        .frame(
                            width: CommandPaletteSuggestionMetrics.faviconImageSize,
                            height: CommandPaletteSuggestionMetrics.faviconImageSize
                        )
                }
                SumiTabTitleLabel(
                    title: tab.name,
                    font: ChromeThemeTypography.commandPaletteSuggestionRowNSFont,
                    textColor: foreground,
                    animated: false
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Text("Switch to Tab")
                    .font(ChromeThemeTypography.commandPaletteSuggestionAction)
                    .foregroundStyle(isSelected ? foreground.opacity(0.86) : tokens.tertiaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                ZStack {
                    Image(systemName: "arrow.right")
                        .font(ChromeThemeTypography.commandPaletteSuggestionControl)
                        .foregroundStyle(isSelected ? chipForeground : tokens.secondaryText)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                .frame(width: 24, height: 24)
                .background(chipBackground)
                .clipShape(CommandPaletteSuggestionMetrics.controlShape)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
