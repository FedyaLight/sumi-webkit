//
//  GenericSuggestionItem.swift
//  Sumi
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI

enum CommandPaletteSuggestionMetrics {
    static let iconContainerSize: CGFloat = 24
    static let symbolIconSize: CGFloat = 14
    static let faviconImageSize: CGFloat = 18
    static let iconCornerRadius: CGFloat = 4
}

struct GenericSuggestionItem: View {
    let icon: Image
    let text: String
    var actionLabel: String? = nil
    var isSelected: Bool = false
    var selectedForeground: Color? = nil
    var selectedChipBackground: Color? = nil
    var selectedChipForeground: Color? = nil
    
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        let tokens = themeContext.tokens(settings: sumiSettings)
        let foreground = isSelected ? (selectedForeground ?? tokens.primaryText) : tokens.secondaryText
        let chipBackground = isSelected ? (selectedChipBackground ?? tokens.commandPaletteChipBackground) : tokens.commandPaletteChipBackground
        let chipForeground = isSelected ? (selectedChipForeground ?? tokens.primaryText) : tokens.tertiaryText

        HStack(alignment: .center, spacing: 12) {
            CommandPaletteFaviconContainer(
                background: isSelected ? chipBackground.opacity(0.9) : .clear
            ) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: CommandPaletteSuggestionMetrics.symbolIconSize,
                        height: CommandPaletteSuggestionMetrics.symbolIconSize
                    )
                    .foregroundStyle(foreground)
            }

            CommandPaletteFadingText(
                text: text,
                foreground: foreground
            )

            if let actionLabel {
                Text(actionLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold))
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
                .clipShape(iconShape)
        }
        .frame(
            width: CommandPaletteSuggestionMetrics.iconContainerSize,
            height: CommandPaletteSuggestionMetrics.iconContainerSize
        )
        .background(background)
        .clipShape(iconShape)
    }

    private var iconShape: RoundedRectangle {
        CommandPaletteSuggestionMetrics.controlShape
    }
}

extension CommandPaletteSuggestionMetrics {
    static var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
    }
}

struct CommandPaletteFadingText: View {
    let text: String
    var foreground: Color
    var font: Font = .system(size: 13, weight: .semibold)
    var height: CGFloat = 17
    var fadeWidth: CGFloat = 30

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask(CommandPaletteTrailingFadeMask(fadeWidth: fadeWidth))
            .frame(height: height)
            .accessibilityLabel(text)
    }
}

struct CommandPaletteTrailingFadeMask: View {
    let fadeWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fadeStart = max(0, min(1, (width - fadeWidth) / width))

            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: fadeStart),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
