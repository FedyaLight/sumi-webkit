import AppKit
import SwiftUI

struct PinnedTileVisual: View {
    private enum TileBackgroundState {
        case active
        case hover
        case idle
    }

    var tabIcon: SwiftUI.Image
    var glyphText: String?
    var chromeTemplateSystemImageName: String?
    var presentationState: ShortcutPresentationState
    var isHovered: Bool = false
    var showsSplitGroupOutline: Bool = false
    var faviconOpacity: Double = 1
    var accentSourceURL: URL?
    var accentSourcePartition: SumiFaviconPartition?
    var faviconImageReader: (any BrowserFaviconImageReading)?
    var selectionBackdrop: Image?

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @Environment(SidebarFaviconImageStore.self) private var faviconImageStore
    @State private var loadedSelectionAccentColor: Color?
    @State private var accentCacheRefreshID = UUID()

    var body: some View {
        tile
            .task(id: selectionAccentLoadKey) {
                await loadSelectionAccentColorIfNeeded()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .faviconCacheUpdated)
            ) { notification in
                guard PinnedTileAccentResolver.faviconUpdate(
                    notification,
                    matches: accentSourceURL
                ) else { return }
                loadedSelectionAccentColor = nil
                PinnedTileAccentResolver.invalidateAccent(for: accentSourceURL)
                accentCacheRefreshID = UUID()
            }
    }

    private var tile: some View {
        let cornerRadius = sumiSettings.resolvedCornerRadius(
            PinnedTileMetrics.cornerRadius
        )
        let resolvedBackdrop = resolvedSelectionBackdrop

        return ZStack {
            if presentationState.isSelected, let resolvedBackdrop {
                FavoriteBackdropSelectionChrome(
                    image: resolvedBackdrop,
                    cornerRadius: cornerRadius,
                    plateColor: backgroundColor,
                    isHovered: isHovered,
                    opacity: faviconOpacity
                )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
                    .overlay {
                        if presentationState.isSelected {
                            RoundedRectangle(
                                cornerRadius: cornerRadius,
                                style: .continuous
                            )
                            .fill(
                                selectionAccentColor.opacity(
                                    0.35 * faviconOpacity
                                )
                            )
                        }
                    }
            }

            HStack {
                Spacer()
                VStack {
                    Spacer()
                    resolvedFaviconSymbol(
                        height: PinnedTileMetrics.faviconHeight
                    )
                    .saturation(
                        showsUnloadedAppearance ? 0.0 : 1.0
                    )
                    .opacity(
                        (showsUnloadedAppearance ? 0.5 : 1.0)
                            * faviconOpacity
                    )
                    Spacer()
                }
                Spacer()
            }

            if showsSplitGroupOutline {
                PinnedTileSplitGroupOutlineMask(
                    corner: cornerRadius,
                    thickness: max(
                        1.25,
                        PinnedTileMetrics.strokeWidth * 0.7
                    ),
                    strokeColor: selectionAccentColor
                )
                .allowsHitTesting(false)
            } else if presentationState.isSelected && resolvedBackdrop == nil {
                PinnedTileSelectionRing(
                    corner: cornerRadius,
                    thickness: PinnedTileMetrics.strokeWidth,
                    color: selectionAccentColor
                )
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PinnedTileMetrics.height)
        .frame(minWidth: PinnedTileMetrics.minWidth)
        .contentShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    private var showsUnloadedAppearance: Bool {
        sumiSettings.showUnloadedTabAppearance
            && presentationState.shouldDesaturateIcon
    }

    private var backgroundColor: Color {
        let state: TileBackgroundState
        if presentationState.isSelected {
            state = .active
        } else if isHovered {
            state = .hover
        } else {
            state = .idle
        }
        switch state {
        case .active:
            return tokens.pinnedActiveBackground
        case .hover:
            return tokens.pinnedHoverBackground
        case .idle:
            return tokens.pinnedIdleBackground
        }
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var drawsAccentChrome: Bool {
        presentationState.isSelected || showsSplitGroupOutline
    }

    private var selectionAccentColor: Color {
        if let loadedSelectionAccentColor {
            return loadedSelectionAccentColor
        }
        return PinnedTileAccentResolver.resolve(
            launchURL: accentSourceURL,
            partition: accentSourcePartition,
            glyphText: glyphText,
            chromeTemplateSystemImageName: chromeTemplateSystemImageName,
            tokens: tokens
        )
    }

    private var resolvedSelectionBackdrop: Image? {
        guard presentationState.isSelected,
              glyphText == nil,
              chromeTemplateSystemImageName == nil
        else { return nil }
        return selectionBackdrop
    }

    private var selectionAccentLoadKey: String {
        [
            accentSourceURL?.absoluteString ?? "no-url",
            accentSourcePartition?.storageComponent ?? "no-partition",
            glyphText == nil ? "no-glyph" : "glyph",
            chromeTemplateSystemImageName ?? "no-template",
            drawsAccentChrome ? "draws-accent" : "no-accent",
            accentCacheRefreshID.uuidString,
        ].joined(separator: "|")
    }

    @MainActor
    private func loadSelectionAccentColorIfNeeded() async {
        guard drawsAccentChrome,
              glyphText == nil,
              chromeTemplateSystemImageName == nil,
              let accentSourceURL,
              let accentSourcePartition,
              let faviconImageReader
        else { return }

        if let cached = PinnedTileAccentResolver.cachedAccent(
            for: accentSourceURL,
            partition: accentSourcePartition
        ) {
            loadedSelectionAccentColor = cached
            return
        }

        await faviconImageStore.load(
            launchURL: accentSourceURL,
            partition: accentSourcePartition,
            imageReader: faviconImageReader
        )

        guard !Task.isCancelled,
              let image = faviconImageStore.nsImage(
                  for: accentSourceURL,
                  partition: accentSourcePartition
              ),
              let accent = SumiFaviconAccentColor.extract(from: image)
        else { return }

        PinnedTileAccentResolver.storeAccent(
            accent,
            for: accentSourceURL,
            partition: accentSourcePartition
        )
        loadedSelectionAccentColor = accent
    }

    private func resolvedFaviconSymbol(height: CGFloat) -> some View {
        PinnedTileFaviconSymbol(
            content: faviconContent,
            height: height,
            foregroundColor: tokens.primaryText
        )
    }

    private var faviconContent: PinnedTileFaviconSymbol.Content {
        if let glyphText {
            return .glyph(glyphText)
        }
        if let systemName = chromeTemplateSystemImageName {
            return .chromeTemplate(systemName)
        }
        return .image(tabIcon)
    }
}

/// Icon drawn at the center of a Favorite/pinned tile. The live tile and the
/// space-transition snapshot tile both render through this view so a space
/// switch cannot change the glyph's metrics: sidebar rows carry a different
/// launcher type scale than tiles do, and a snapshot that borrowed the row
/// scale drew user glyphs a pixel or two off from the live grid.
struct PinnedTileFaviconSymbol: View {
    enum Content {
        case image(Image)
        case glyph(String)
        /// Drawn with `ChromeThemeTokens.primaryText` + monochrome.
        case chromeTemplate(String)
    }

    let content: Content
    var height: CGFloat = PinnedTileMetrics.faviconHeight
    let foregroundColor: Color

    var body: some View {
        Group {
            switch content {
            case .glyph(let glyphText):
                Text(glyphText)
                    .font(
                        SidebarThemeTokens.Typography.pinnedTileGlyphText(
                            size: height
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .multilineTextAlignment(.center)
            case .chromeTemplate(let systemName):
                Image(systemName: systemName)
                    .font(
                        SidebarThemeTokens.Typography.chromeTemplateIcon(
                            size: height
                        )
                    )
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(foregroundColor)
            case .image(let image):
                image
            }
        }
        .frame(width: height, height: height)
    }
}
