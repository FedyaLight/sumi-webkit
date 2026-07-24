//
//  HistorySuggestionItem.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct HistorySuggestionItem: View {
    let faviconContext: CommandPaletteFaviconContext
    let entry: HistoryListItem
    var isSelected: Bool = false
    var isHovered: Bool = false
    var selectedForeground: Color?
    var onDelete: (() -> Void)?

    @State private var resolvedFavicon: NSImage?
    @State private var isDeleteConfirming = false
    @State private var isDeleteHovered = false
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var colors: ColorConfig {
        let tokens = themeContext.tokens(settings: sumiSettings)
        return ColorConfig(
            tokens: tokens,
            isSelected: isSelected,
            selectedForeground: selectedForeground
        )
    }

    private var isDeleteVisible: Bool {
        isHovered || isDeleteConfirming
    }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            CommandPaletteFaviconContainer {
                faviconImage
                    .foregroundStyle(colors.faviconColor)
                    .frame(
                        width: CommandPaletteSuggestionMetrics.faviconImageSize,
                        height: CommandPaletteSuggestionMetrics.faviconImageSize
                    )
                    .accessibilityHidden(true)
            }

            historyLine
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

            if let onDelete, isDeleteVisible {
                deleteControl(onDelete: onDelete)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: entry.url) {
            await fetchFavicon(for: entry.url)
        }
        .onChange(of: entry.id) { _, _ in
            isDeleteConfirming = false
            isDeleteHovered = false
        }
        .onChange(of: isHovered) { _, newValue in
            guard !newValue, !isDeleteConfirming else { return }
            isDeleteHovered = false
        }
    }

    @ViewBuilder
    private var faviconImage: some View {
        if let resolvedFavicon {
            Image(nsImage: resolvedFavicon)
                .accessibilityHidden(true)
        } else {
            Image(nsImage: SumiFaviconResolver.menuImage(
                for: entry.url,
                partition: faviconContext.partition,
                imageReader: faviconContext.imageReader
            ))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func deleteControl(onDelete: @escaping () -> Void) -> some View {
        ZStack(alignment: .trailing) {
            if isDeleteConfirming {
                HStack(spacing: 4) {
                    Button {
                        isDeleteConfirming = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(ChromeThemeTypography.commandPaletteDeleteControlSmall)
                            .foregroundStyle(colors.deleteButtonColor(isHovered: false))
                            .frame(width: 24, height: 24)
                            .background(colors.deleteButtonBackground(isHovered: false))
                            .clipShape(CommandPaletteSuggestionMetrics.controlShape)
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel history deletion")
                    .help("Cancel history deletion")

                    Button {
                        onDelete()
                        isDeleteConfirming = false
                    } label: {
                        Image(systemName: "checkmark")
                            .font(ChromeThemeTypography.commandPaletteDeleteControl)
                            .foregroundStyle(CommandPaletteThemeTokens.Colors.deleteConfirmationForeground)
                            .frame(width: 24, height: 24)
                            .background(colors.confirmDeleteBackground)
                            .clipShape(CommandPaletteSuggestionMetrics.controlShape)
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Confirm history deletion")
                    .help("Confirm history deletion")
                }
            } else {
                Button {
                    isDeleteConfirming = true
                } label: {
                    Image(systemName: "trash")
                        .font(ChromeThemeTypography.commandPaletteDeleteAction)
                        .foregroundStyle(colors.deleteButtonColor(isHovered: isDeleteHovered))
                        .frame(width: 24, height: 24)
                        .background(colors.deleteButtonBackground(isHovered: isDeleteHovered))
                        .clipShape(CommandPaletteSuggestionMetrics.controlShape)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete history entry")
                .help("Delete history entry")
                .onHover { hovering in
                    isDeleteHovered = hovering
                }
            }
        }
        .frame(width: 58, alignment: .trailing)
    }

    private var historyLine: some View {
        CommandPaletteHistoryLineText(
            title: entry.displayTitle,
            url: entry.displayURL,
            titleColor: colors.titleColor,
            urlColor: colors.urlColor
        )
    }

    private func fetchFavicon(for url: URL) async {
        guard SumiFaviconResolver.cacheKey(for: url) != nil else {
            await MainActor.run { self.resolvedFavicon = nil }
            return
        }

        guard let image = await SumiFaviconResolver.image(
            for: url,
            partition: faviconContext.partition,
            imageReader: faviconContext.imageReader,
            prefetch: faviconContext.prefetch
        ) else {
            await MainActor.run { self.resolvedFavicon = nil }
            return
        }

        await MainActor.run {
            self.resolvedFavicon = image
        }
    }
}

private struct CommandPaletteHistoryLineText: View {
    let title: String
    let url: String
    let titleColor: Color
    let urlColor: Color

    var body: some View {
        Text(attributedLine)
            .font(ChromeThemeTypography.commandPaletteSuggestionRow)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: CommandPaletteSuggestionMetrics.rowLineBoxHeight,
                maxHeight: CommandPaletteSuggestionMetrics.rowLineBoxHeight,
                alignment: .leading
            )
            .accessibilityLabel("\(title) - \(url)")
    }

    private var attributedLine: AttributedString {
        var line = AttributedString(title)
        line.foregroundColor = titleColor

        var suffix = AttributedString(" - \(url)")
        suffix.foregroundColor = urlColor
        line.append(suffix)
        return line
    }
}

// MARK: - Colors from chrome tokens (command palette row + chip tokens)
private struct ColorConfig {
    let tokens: ChromeThemeTokens
    let isSelected: Bool
    let selectedForeground: Color?

    init(
        tokens: ChromeThemeTokens,
        isSelected: Bool,
        selectedForeground: Color? = nil
    ) {
        self.tokens = tokens
        self.isSelected = isSelected
        self.selectedForeground = selectedForeground
    }

    var titleColor: Color {
        isSelected ? (selectedForeground ?? tokens.primaryText) : tokens.secondaryText
    }

    var urlColor: Color {
        isSelected ? (selectedForeground ?? tokens.primaryText).opacity(0.86) : tokens.tertiaryText
    }

    var faviconColor: Color {
        isSelected ? (selectedForeground ?? tokens.primaryText) : tokens.secondaryText
    }

    func deleteButtonColor(isHovered: Bool) -> Color {
        if isHovered {
            return Color.red.opacity(0.9)
        }
        return isSelected ? (selectedForeground ?? tokens.primaryText).opacity(0.9) : tokens.tertiaryText
    }

    func deleteButtonBackground(isHovered: Bool) -> Color {
        if isHovered {
            return Color.red.opacity(0.14)
        }
        return isSelected ? .clear : tokens.floatingSurfaceSecondaryBackground.opacity(0.72)
    }

    var confirmDeleteBackground: Color {
        Color.red.opacity(isSelected ? 0.92 : 0.86)
    }
}
