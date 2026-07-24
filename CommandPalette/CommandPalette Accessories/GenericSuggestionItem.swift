//
//  GenericSuggestionItem.swift
//  Sumi
//
//

import SwiftUI

enum CommandPaletteSuggestionMetrics {
    static let iconContainerSize: CGFloat = 24
    static let symbolIconSize: CGFloat = 14
    static let faviconImageSize: CGFloat = 18
    static let iconCornerRadius: CGFloat = 4
    static let rowLineBoxHeight: CGFloat = 17
}

struct GenericSuggestionItem: View {
    let systemImage: String
    let text: String
    var actionLabel: String?
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

        HStack(alignment: .center, spacing: 12) {
            CommandPaletteFaviconContainer {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: CommandPaletteSuggestionMetrics.symbolIconSize,
                        height: CommandPaletteSuggestionMetrics.symbolIconSize
                    )
                    .foregroundStyle(foreground)
                    .accessibilityHidden(true)
            }

            Text(text)
                .font(ChromeThemeTypography.commandPaletteSuggestionRow)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .frame(height: CommandPaletteSuggestionMetrics.rowLineBoxHeight, alignment: .leading)
                .accessibilityLabel(text)

            if let actionLabel {
                Text(actionLabel.uppercased())
                    .font(ChromeThemeTypography.commandPaletteSuggestionChip)
                    .foregroundStyle(chipForeground)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(chipBackground)
                    .clipShape(CommandPaletteSuggestionMetrics.controlShape)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CommandPaletteFaviconContainer<Content: View>: View {
    var background: Color = .clear
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            content
        }
        .frame(
            width: CommandPaletteSuggestionMetrics.iconContainerSize,
            height: CommandPaletteSuggestionMetrics.iconContainerSize
        )
        .background(background)
    }
}

extension CommandPaletteSuggestionMetrics {
    static var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
    }
}
