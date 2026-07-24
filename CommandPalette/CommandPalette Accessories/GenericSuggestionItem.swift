//
//  GenericSuggestionItem.swift
//  Sumi
//
//

import AppKit
import SumiDomain
import SwiftUI

enum CommandPaletteSuggestionMetrics {
    static let iconContainerSize: CGFloat = 24
    static let symbolIconSize: CGFloat = 14
    static let faviconImageSize: CGFloat = 18
    static let iconCornerRadius: CGFloat = 4
    static let rowLineBoxHeight: CGFloat = 17
}

struct CommandPaletteFaviconContainer<Content: View>: View {
    var size = CommandPaletteSuggestionMetrics.iconContainerSize
    var background: Color = .clear
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            content
        }
        .frame(
            width: size,
            height: size
        )
        .background(background)
    }
}

extension CommandPaletteSuggestionMetrics {
    static var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
    }
}

struct CommandPaletteRowItem: View {
    let faviconContext: CommandPaletteFaviconContext
    let row: CommandPaletteRow
    var isSelected = false
    var isHovered = false
    var selectedForeground: Color?
    var selectedChipBackground: Color?
    var selectedChipForeground: Color?
    var onDeleteHistory: ((HistoryQuery) -> Void)?

    @State private var resolvedFavicon: NSImage?
    @State private var isDeleteConfirming = false
    @State private var isDeleteHovered = false
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        let tokens = themeContext.tokens(settings: sumiSettings)
        let foreground = isSelected
            ? (selectedForeground ?? tokens.primaryText)
            : tokens.secondaryText
        let secondaryForeground = isSelected
            ? foreground.opacity(0.86)
            : tokens.tertiaryText
        let chipBackground = isSelected
            ? (selectedChipBackground
                ?? tokens.floatingSurfaceSecondaryBackground)
            : tokens.floatingSurfaceSecondaryBackground
        let chipForeground = isSelected
            ? (selectedChipForeground ?? tokens.primaryText)
            : tokens.tertiaryText

        HStack(alignment: .center, spacing: 9) {
            CommandPaletteFaviconContainer(size: iconContainerSize) {
                rowIcon(foreground: foreground, tokens: tokens)
            }
            .accessibilityHidden(true)

            rowText(
                foreground: foreground,
                secondaryForeground: secondaryForeground
            )
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)

            if case .deleteHistory(let query) = row.secondaryAction,
               isHovered || isDeleteConfirming,
               let onDeleteHistory {
                deleteControl(
                    query: query,
                    foreground: foreground,
                    tokens: tokens,
                    onDeleteHistory: onDeleteHistory
                )
                .fixedSize(horizontal: true, vertical: false)
            } else {
                accessory(
                    foreground: foreground,
                    chipBackground: chipBackground,
                    chipForeground: chipForeground,
                    tokens: tokens
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: faviconURL) {
            await fetchFavicon()
        }
        .onChange(of: row.id) { _, _ in
            isDeleteConfirming = false
            isDeleteHovered = false
        }
        .onChange(of: isHovered) { _, hovering in
            guard !hovering, !isDeleteConfirming else { return }
            isDeleteHovered = false
        }
    }

    @ViewBuilder
    private func rowIcon(
        foreground: Color,
        tokens: ChromeThemeTokens
    ) -> some View {
        switch row.icon {
        case .systemSymbol(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .frame(
                    width: CommandPaletteSuggestionMetrics.symbolIconSize,
                    height: CommandPaletteSuggestionMetrics.symbolIconSize
                )
                .foregroundStyle(foreground)
        case .splitView(let members):
            CommandPaletteSplitIconView(
                members: members,
                faviconContext: faviconContext,
                foreground: foreground,
                background: isSelected
                    ? Color.white.opacity(0.94)
                    : tokens.floatingSurfaceSecondaryBackground,
                border: isSelected
                    ? Color.white.opacity(0.72)
                    : tokens.separator.opacity(0.72)
            )
        case .tab(let presentation):
            faviconImage(for: presentation)
                .foregroundStyle(foreground)
        case .favicon(let url):
            if let resolvedFavicon {
                Image(nsImage: resolvedFavicon)
                    .resizable()
                    .frame(
                        width: CommandPaletteSuggestionMetrics.faviconImageSize,
                        height: CommandPaletteSuggestionMetrics.faviconImageSize
                    )
            } else {
                Image(
                    nsImage: SumiFaviconResolver.menuImage(
                        for: url,
                        partition: faviconContext.partition,
                        imageReader: faviconContext.imageReader
                    )
                )
                .resizable()
                .frame(
                    width: CommandPaletteSuggestionMetrics.faviconImageSize,
                    height: CommandPaletteSuggestionMetrics.faviconImageSize
                )
                .foregroundStyle(foreground)
            }
        }
    }

    @ViewBuilder
    private func faviconImage(
        for presentation: TabFaviconPresentation
    ) -> some View {
        switch presentation {
        case .systemSymbol(let name):
            Image(systemName: name)
                .frame(
                    width: CommandPaletteSuggestionMetrics.faviconImageSize,
                    height: CommandPaletteSuggestionMetrics.faviconImageSize
                )
        case .bitmap(let image):
            Image(nsImage: image)
                .resizable()
                .frame(
                    width: CommandPaletteSuggestionMetrics.faviconImageSize,
                    height: CommandPaletteSuggestionMetrics.faviconImageSize
                )
        }
    }

    @ViewBuilder
    private func rowText(
        foreground: Color,
        secondaryForeground: Color
    ) -> some View {
        if let subtitle = row.subtitle {
            Text(historyLine(
                title: row.title,
                subtitle: subtitle,
                foreground: foreground,
                secondaryForeground: secondaryForeground
            ))
            .font(ChromeThemeTypography.commandPaletteSuggestionRow)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
                minHeight: CommandPaletteSuggestionMetrics.rowLineBoxHeight,
                maxHeight: CommandPaletteSuggestionMetrics.rowLineBoxHeight,
                alignment: .leading
            )
        } else {
            Text(row.title)
                .font(ChromeThemeTypography.commandPaletteSuggestionRow)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(
                    minHeight: CommandPaletteSuggestionMetrics.rowLineBoxHeight,
                    maxHeight: CommandPaletteSuggestionMetrics.rowLineBoxHeight,
                    alignment: .leading
                )
        }
    }

    @ViewBuilder
    private func accessory(
        foreground: Color,
        chipBackground: Color,
        chipForeground: Color,
        tokens: ChromeThemeTokens
    ) -> some View {
        switch row.accessory {
        case .none:
            EmptyView()
        case .chip(let label):
            Text(label.uppercased())
                .font(ChromeThemeTypography.commandPaletteSuggestionChip)
                .foregroundStyle(chipForeground)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(chipBackground)
                .clipShape(CommandPaletteSuggestionMetrics.controlShape)
                .accessibilityHidden(true)
        case .arrow(let label):
            HStack(spacing: 10) {
                Text(label)
                    .font(
                        ChromeThemeTypography
                            .commandPaletteSuggestionAction
                    )
                    .foregroundStyle(
                        isSelected
                            ? foreground.opacity(0.86)
                            : tokens.tertiaryText
                    )
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "arrow.right")
                    .font(
                        ChromeThemeTypography
                            .commandPaletteSuggestionControl
                    )
                    .foregroundStyle(
                        isSelected ? chipForeground : tokens.secondaryText
                    )
                    .frame(width: 24, height: 24)
                    .background(chipBackground)
                    .clipShape(CommandPaletteSuggestionMetrics.controlShape)
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func deleteControl(
        query: HistoryQuery,
        foreground: Color,
        tokens: ChromeThemeTokens,
        onDeleteHistory: @escaping (HistoryQuery) -> Void
    ) -> some View {
        ZStack(alignment: .trailing) {
            if isDeleteConfirming {
                HStack(spacing: 4) {
                    Button {
                        isDeleteConfirming = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(
                                ChromeThemeTypography
                                    .commandPaletteDeleteControlSmall
                            )
                            .foregroundStyle(foreground.opacity(0.9))
                            .frame(width: 24, height: 24)
                            .background(
                                tokens.floatingSurfaceSecondaryBackground
                                    .opacity(0.72)
                            )
                            .clipShape(
                                CommandPaletteSuggestionMetrics.controlShape
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel history deletion")

                    Button {
                        onDeleteHistory(query)
                        isDeleteConfirming = false
                    } label: {
                        Image(systemName: "checkmark")
                            .font(
                                ChromeThemeTypography
                                    .commandPaletteDeleteControl
                            )
                            .foregroundStyle(
                                CommandPaletteThemeTokens.Colors
                                    .deleteConfirmationForeground
                            )
                            .frame(width: 24, height: 24)
                            .background(
                                Color.red.opacity(isSelected ? 0.92 : 0.86)
                            )
                            .clipShape(
                                CommandPaletteSuggestionMetrics.controlShape
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Confirm history deletion")
                }
            } else {
                Button {
                    isDeleteConfirming = true
                } label: {
                    Image(systemName: "trash")
                        .font(
                            ChromeThemeTypography.commandPaletteDeleteAction
                        )
                        .foregroundStyle(
                            isDeleteHovered
                                ? Color.red.opacity(0.9)
                                : foreground.opacity(0.9)
                        )
                        .frame(width: 24, height: 24)
                        .background(
                            isDeleteHovered
                                ? Color.red.opacity(0.14)
                                : tokens.floatingSurfaceSecondaryBackground
                                    .opacity(0.72)
                        )
                        .clipShape(
                            CommandPaletteSuggestionMetrics.controlShape
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete history entry")
                .onHover { isDeleteHovered = $0 }
            }
        }
        .frame(width: 58, alignment: .trailing)
    }

    private var faviconURL: URL? {
        guard case .favicon(let url) = row.icon else { return nil }
        return url
    }

    private var iconContainerSize: CGFloat {
        if case .splitView = row.icon {
            return 30
        }
        return CommandPaletteSuggestionMetrics.iconContainerSize
    }

    private func fetchFavicon() async {
        guard let faviconURL,
              let image = await SumiFaviconResolver.image(
                  for: faviconURL,
                  partition: faviconContext.partition,
                  imageReader: faviconContext.imageReader,
                  prefetch: faviconContext.prefetch
              ) else {
            await MainActor.run { resolvedFavicon = nil }
            return
        }
        await MainActor.run { resolvedFavicon = image }
    }

    private func historyLine(
        title: String,
        subtitle: String,
        foreground: Color,
        secondaryForeground: Color
    ) -> AttributedString {
        var line = AttributedString(title)
        line.foregroundColor = foreground
        var suffix = AttributedString(" - \(subtitle)")
        suffix.foregroundColor = secondaryForeground
        line.append(suffix)
        return line
    }
}

private struct CommandPaletteSplitIconView: View {
    let members: [CommandPaletteSplitMemberPresentation]
    let faviconContext: CommandPaletteFaviconContext
    let foreground: Color
    let background: Color
    let border: Color

    private let size: CGFloat = 30
    private let cornerRadius: CGFloat = 5
    private let separatorWidth: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let visibleMembers = Array(
                members.prefix(SplitGroup.maximumMembers)
            )
            let rects = SplitTileGeometry.resolve(
                in: geometry.size,
                count: visibleMembers.count,
                thickness: separatorWidth
            ).contentRects

            ZStack {
                ForEach(
                    Array(visibleMembers.enumerated()),
                    id: \.element.id
                ) { index, member in
                    if rects.indices.contains(index) {
                        let rect = rects[index]
                        ZStack {
                            Rectangle()
                                .fill(background)
                            CommandPaletteSplitMemberIconView(
                                presentation: member,
                                faviconContext: faviconContext,
                                foreground: foreground
                            )
                            .frame(
                                width: min(13, rect.width - 2),
                                height: min(13, rect.height - 2)
                            )
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .strokeBorder(border, lineWidth: 0.5)
        }
    }
}

private struct CommandPaletteSplitMemberIconView: View {
    let presentation: CommandPaletteSplitMemberPresentation
    let faviconContext: CommandPaletteFaviconContext
    let foreground: Color

    @State private var resolvedFavicon: NSImage?

    var body: some View {
        Group {
            switch presentation.icon {
            case .glyph(let glyph):
                Text(glyph)
                    .font(.system(size: 10))
            case .systemSymbol(let name):
                Image(systemName: name)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(foreground)
            case .tab(let favicon):
                tabIcon(favicon)
                    .foregroundStyle(foreground)
            case .favicon(let url):
                Image(
                    nsImage: resolvedFavicon
                        ?? SumiFaviconResolver.menuImage(
                            for: url,
                            partition: faviconContext.partition,
                            imageReader: faviconContext.imageReader
                        )
                )
                .resizable()
                .scaledToFit()
                .foregroundStyle(foreground)
            }
        }
        .clipShape(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
        )
        .task(id: faviconURL) {
            await fetchFavicon()
        }
    }

    @ViewBuilder
    private func tabIcon(
        _ presentation: TabFaviconPresentation
    ) -> some View {
        switch presentation {
        case .systemSymbol(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
        case .bitmap(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        }
    }

    private var faviconURL: URL? {
        guard case .favicon(let url) = presentation.icon else {
            return nil
        }
        return url
    }

    private func fetchFavicon() async {
        guard let faviconURL,
              let image = await SumiFaviconResolver.image(
                  for: faviconURL,
                  partition: faviconContext.partition,
                  imageReader: faviconContext.imageReader,
                  prefetch: faviconContext.prefetch
              ) else {
            await MainActor.run { resolvedFavicon = nil }
            return
        }
        await MainActor.run { resolvedFavicon = image }
    }
}
