//
//  HistorySuggestionItem.swift
//  Sumi
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import AppKit
import SwiftUI

struct HistorySuggestionItem: View {
    let entry: HistoryListItem
    var isSelected: Bool = false
    var isHovered: Bool = false
    var selectedForeground: Color? = nil
    var onDelete: (() -> Void)? = nil
    
    @State private var resolvedFavicon: SwiftUI.Image? = nil
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
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(colors.faviconColor)
                    .frame(
                        width: CommandPaletteSuggestionMetrics.faviconImageSize,
                        height: CommandPaletteSuggestionMetrics.faviconImageSize
                    )
            }
            
            historyLine
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

            if let onDelete, isDeleteVisible {
                deleteControl(onDelete: onDelete)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
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

    private var faviconImage: Image {
        if let resolvedFavicon {
            return resolvedFavicon
        }
        return Image(nsImage: SumiFaviconResolver.menuImage(for: entry.url))
    }

    @ViewBuilder
    private func deleteControl(onDelete: @escaping () -> Void) -> some View {
        ZStack(alignment: .trailing) {
            if isDeleteConfirming {
                Button {
                    onDelete()
                    isDeleteConfirming = false
                } label: {
                    Text("Delete")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(colors.confirmDeleteBackground)
                        .clipShape(CommandPaletteSuggestionMetrics.controlShape)
                }
                .buttonStyle(.plain)
                .help("Confirm history deletion")
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isDeleteConfirming = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.deleteButtonColor(isHovered: isDeleteHovered))
                        .frame(width: 24, height: 24)
                        .background(colors.deleteButtonBackground(isHovered: isDeleteHovered))
                        .clipShape(CommandPaletteSuggestionMetrics.controlShape)
                }
                .buttonStyle(.plain)
                .help("Delete history entry")
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isDeleteHovered = hovering
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: 58, alignment: .trailing)
        .animation(.easeInOut(duration: 0.12), value: isDeleteConfirming)
        .animation(.easeInOut(duration: 0.12), value: isDeleteVisible)
    }

    private var historyLine: some View {
        CommandPaletteHistoryLineText(
            title: entry.displayTitle,
            url: entry.displayURL,
            titleColor: colors.titleColor,
            urlColor: colors.urlColor
        )
        .accessibilityLabel("\(entry.displayTitle) - \(entry.displayURL)")
    }
    
    private func fetchFavicon(for url: URL) async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        guard SumiFaviconResolver.cacheKey(for: url) != nil else {
            await MainActor.run { self.resolvedFavicon = defaultFavicon }
            return
        }

        guard let image = await SumiFaviconResolver.image(for: url) else {
            await MainActor.run { self.resolvedFavicon = defaultFavicon }
            return
        }

        await MainActor.run {
            self.resolvedFavicon = SwiftUI.Image(nsImage: image)
        }
    }
}

private struct CommandPaletteHistoryLineText: View {
    let title: String
    let url: String
    let titleColor: Color
    let urlColor: Color

    var body: some View {
        CommandPaletteHistoryLineRepresentable(
            title: title,
            url: url,
            titleColor: titleColor,
            urlColor: urlColor,
            font: .systemFont(ofSize: 13, weight: .semibold),
            fadeWidth: 42
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 17, maxHeight: 17, alignment: .leading)
        .clipped()
    }
}

private struct CommandPaletteHistoryLineRepresentable: NSViewRepresentable {
    let title: String
    let url: String
    let titleColor: Color
    let urlColor: Color
    let font: NSFont
    let fadeWidth: CGFloat

    func makeNSView(context _: Context) -> CommandPaletteHistoryLineNSView {
        let view = CommandPaletteHistoryLineNSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView _: CommandPaletteHistoryLineNSView,
        context _: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: 17)
    }

    func updateNSView(_ nsView: CommandPaletteHistoryLineNSView, context _: Context) {
        nsView.apply(
            title: title,
            url: url,
            titleColor: NSColor(titleColor),
            urlColor: NSColor(urlColor),
            font: font,
            fadeWidth: fadeWidth
        )
    }
}

private final class CommandPaletteHistoryLineNSView: NSView {
    private let textField = NSTextField()
    private var fadeWidth: CGFloat = 30

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 17)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        applyTrailingFadeMask()
    }

    func apply(
        title: String,
        url: String,
        titleColor: NSColor,
        urlColor: NSColor,
        font: NSFont,
        fadeWidth: CGFloat
    ) {
        self.fadeWidth = fadeWidth

        let attributed = NSMutableAttributedString()
        attributed.append(
            NSAttributedString(
                string: title,
                attributes: [
                    .font: font,
                    .foregroundColor: titleColor
                ]
            )
        )
        attributed.append(
            NSAttributedString(
                string: " - ",
                attributes: [
                    .font: font,
                    .foregroundColor: urlColor
                ]
            )
        )
        attributed.append(
            NSAttributedString(
                string: url,
                attributes: [
                    .font: font,
                    .foregroundColor: urlColor
                ]
            )
        )

        textField.attributedStringValue = attributed
        applyTrailingFadeMask()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        textField.wantsLayer = true
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.alignment = .left
        textField.lineBreakMode = .byClipping
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if let cell = textField.cell as? NSTextFieldCell {
            cell.lineBreakMode = .byClipping
            cell.wraps = false
            cell.usesSingleLineMode = true
            cell.truncatesLastVisibleLine = false
        }

        addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func applyTrailingFadeMask() {
        guard let layer else { return }
        layer.masksToBounds = true
        let mask: CAGradientLayer
        if let existing = layer.mask as? CAGradientLayer {
            mask = existing
        } else {
            mask = CAGradientLayer()
            layer.mask = mask
        }

        mask.frame = layer.bounds
        let width = max(mask.bounds.width, 1)
        let fadeStart = max(0, min(1, (width - fadeWidth) / width))
        mask.startPoint = CGPoint(x: fadeStart, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [NSColor.white.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, 1]
    }
}

// MARK: - Colors from chrome tokens (palette list uses command-palette row + chip tokens)
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
        return isSelected ? .clear : tokens.commandPaletteChipBackground.opacity(0.72)
    }

    var confirmDeleteBackground: Color {
        Color.red.opacity(isSelected ? 0.92 : 0.86)
    }
}
