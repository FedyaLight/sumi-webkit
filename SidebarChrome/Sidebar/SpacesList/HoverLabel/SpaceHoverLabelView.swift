//
//  SpaceHoverLabelView.swift
//  Sumi
//
//  The hover label itself: a tinted plate above the spaces strip carrying the
//  space's name and one chip per key of its shortcut.
//

import SwiftUI

private enum SpaceHoverLabelLayout {
    static let plateCornerRadius: CGFloat = 16
    static let plateHorizontalPadding: CGFloat = 12
    static let plateVerticalPadding: CGFloat = 7
    static let contentSpacing: CGFloat = 8
    static let chipSpacing: CGFloat = 4
    static let chipCornerRadius: CGFloat = 6
    /// Hairline around the key's face.
    static let chipEdgeWidth: CGFloat = 1
    /// The key's "beard": the face sits this far off the bottom, so the darker
    /// body shows through as a lip and the chip reads as a physical keycap.
    static let chipBeardHeight: CGFloat = 3
    static let chipMinWidth: CGFloat = 20
    static let chipHorizontalPadding: CGFloat = 5
    static let chipVerticalPadding: CGFloat = 1
    static let titleFont = ChromeThemeTypography.spaceHoverLabelTitle
    static let chipFont = ChromeThemeTypography.spaceHoverLabelShortcutChip
}

/// Owns the complete hover-label presentation behind one input: the icon anchor
/// published by the strip. Callers do not measure the strip, label, or bar.
struct SpaceHoverLabelPresenter: View {
    let anchor: SpaceHoverLabelAnchor?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if let anchor {
                ThemedSpaceHoverLabelPlate(
                    label: anchor.label,
                    target: proxy[anchor.bounds]
                )
                .sumiNativeSurfaceColorScheme()
                .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? nil : .linear(duration: 0.10),
            value: anchor?.label.spaceID
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Keeps theme subscriptions out of the idle presenter. This view exists only
/// while a label is visible, so theme updates do no hover-label work otherwise.
private struct ThemedSpaceHoverLabelPlate: View {
    let label: SpaceHoverLabel
    let target: CGRect

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        SpaceHoverLabelPositioningLayout(target: target) {
            SpaceHoverLabelPlate(
                label: label,
                palette: SpaceHoverLabelPalette.make(
                    tokens: themeContext.tokens(settings: sumiSettings)
                )
            )
        }
    }
}

private struct SpaceHoverLabelPositioningLayout: Layout {
    let target: CGRect

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions(
            by: subviews.first?.sizeThatFits(.unspecified) ?? .zero
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let plate = subviews.first else { return }
        // Give the plate the real sidebar width. The title is the flexible
        // child, so long space names truncate while shortcut keycaps stay
        // intact instead of the plate escaping the window.
        let plateSize = plate.sizeThatFits(
            ProposedViewSize(width: bounds.width, height: nil)
        )
        let centerX = bounds.minX + SpaceHoverLabelPlacement.centerX(
            anchorX: target.midX,
            containerWidth: bounds.width,
            labelWidth: plateSize.width
        )
        let centerY = bounds.minY + target.minY
            - SpaceHoverLabelPlacement.verticalOffset
            - plateSize.height / 2
        plate.place(
            at: CGPoint(x: centerX, y: centerY),
            anchor: .center,
            proposal: ProposedViewSize(plateSize)
        )
    }
}

struct SpaceHoverLabelPlate: View {
    let label: SpaceHoverLabel
    let palette: SpaceHoverLabelPalette

    var body: some View {
        ZStack {
            SpaceHoverLabelContent(label: label, palette: palette)
                .id(label.spaceID)
                .transition(.opacity)
        }
        .padding(.horizontal, SpaceHoverLabelLayout.plateHorizontalPadding)
        .padding(.vertical, SpaceHoverLabelLayout.plateVerticalPadding)
        .background(plateBackground)
    }

    /// The surface keeps one identity during icon hand-off. Only its complete
    /// content cross-fades, so two translucent plate backgrounds never stack
    /// and expose the chrome as a flash between them.
    private var plateBackground: some View {
        RoundedRectangle(
            cornerRadius: SpaceHoverLabelLayout.plateCornerRadius,
            style: .continuous
        )
        .fill(palette.surface)
        .overlay {
            RoundedRectangle(
                cornerRadius: SpaceHoverLabelLayout.plateCornerRadius,
                style: .continuous
            )
            .strokeBorder(palette.surfaceBorder, lineWidth: 1)
        }
    }
}

private struct SpaceHoverLabelContent: View {
    let label: SpaceHoverLabel
    let palette: SpaceHoverLabelPalette

    var body: some View {
        HStack(spacing: SpaceHoverLabelLayout.contentSpacing) {
            Text(label.title)
                .font(SpaceHoverLabelLayout.titleFont)
                .foregroundStyle(palette.titleText)
                .lineLimit(1)
                .truncationMode(.tail)

            if !label.shortcutGlyphs.isEmpty {
                HStack(spacing: SpaceHoverLabelLayout.chipSpacing) {
                    ForEach(label.shortcutGlyphs.indices, id: \.self) { index in
                        SpaceHoverLabelChip(
                            glyph: label.shortcutGlyphs[index],
                            palette: palette
                        )
                    }
                }
            }
        }
    }
}

struct SpaceHoverLabelChip: View {
    let glyph: String
    let palette: SpaceHoverLabelPalette

    var body: some View {
        Text(glyph)
            .font(SpaceHoverLabelLayout.chipFont)
            .foregroundStyle(palette.chipText)
            .padding(.horizontal, SpaceHoverLabelLayout.chipHorizontalPadding)
            .padding(.top, SpaceHoverLabelLayout.chipVerticalPadding)
            // The extra bottom padding is the beard, so the glyph stays centred
            // on the face rather than on the whole keycap.
            .padding(
                .bottom,
                SpaceHoverLabelLayout.chipVerticalPadding
                    + SpaceHoverLabelLayout.chipBeardHeight
                    - SpaceHoverLabelLayout.chipEdgeWidth
            )
            .frame(minWidth: SpaceHoverLabelLayout.chipMinWidth)
            .background(keycap)
    }

    /// A darker body with the lighter face inset into it — deeper at the bottom,
    /// which is what gives the key its lip.
    private var keycap: some View {
        RoundedRectangle(
            cornerRadius: SpaceHoverLabelLayout.chipCornerRadius,
            style: .continuous
        )
        .fill(palette.chipBorder)
        .overlay {
            RoundedRectangle(
                cornerRadius: SpaceHoverLabelLayout.chipCornerRadius
                    - SpaceHoverLabelLayout.chipEdgeWidth,
                style: .continuous
            )
            .fill(palette.chipFill)
            .padding(
                EdgeInsets(
                    top: SpaceHoverLabelLayout.chipEdgeWidth,
                    leading: SpaceHoverLabelLayout.chipEdgeWidth,
                    bottom: SpaceHoverLabelLayout.chipBeardHeight,
                    trailing: SpaceHoverLabelLayout.chipEdgeWidth
                )
            )
        }
    }
}
