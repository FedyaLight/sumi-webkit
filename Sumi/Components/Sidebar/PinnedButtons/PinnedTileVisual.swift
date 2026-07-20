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
    var selectionBackdrop: Image? = nil

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
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
                EssentialBackdropSelectionChrome(
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
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .continuous
                        )
                    )
            }

            HStack {
                Spacer()
                VStack {
                    Spacer()
                    resolvedFaviconSymbol(
                        height: PinnedTileMetrics.faviconHeight
                    )
                    .saturation(
                        presentationState.shouldDesaturateIcon ? 0.0 : 1.0
                    )
                    .opacity(
                        (presentationState.shouldDesaturateIcon ? 0.8 : 1.0)
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

        let cachedImage = TabFaviconStore.getCachedImage(
            forDocumentURL: accentSourceURL,
            partition: accentSourcePartition,
            context: .pinnedLauncher,
            imageReader: faviconImageReader
        )
        let image: NSImage?
        if let cachedImage {
            image = cachedImage
        } else {
            image = await TabFaviconStore.loadCachedLauncherImage(
                forDocumentURL: accentSourceURL,
                partition: accentSourcePartition,
                imageReader: faviconImageReader
            )
        }

        guard !Task.isCancelled,
              let image,
              let accent = SumiFaviconAccentColor.extract(from: image)
        else { return }

        PinnedTileAccentResolver.storeAccent(
            accent,
            for: accentSourceURL,
            partition: accentSourcePartition
        )
        loadedSelectionAccentColor = accent
    }

    @ViewBuilder
    private func resolvedFaviconSymbol(height: CGFloat) -> some View {
        Group {
            if let glyphText {
                Text(glyphText)
                    .font(
                        SidebarThemeTokens.Typography.pinnedTileGlyphText(
                            size: height
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .multilineTextAlignment(.center)
            } else if let systemName = chromeTemplateSystemImageName {
                Image(systemName: systemName)
                    .font(
                        SidebarThemeTokens.Typography.chromeTemplateIcon(
                            size: height
                        )
                    )
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tokens.primaryText)
            } else {
                tabIcon
            }
        }
        .frame(width: height, height: height)
    }
}
