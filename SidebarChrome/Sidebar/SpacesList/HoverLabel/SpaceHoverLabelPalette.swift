//
//  SpaceHoverLabelPalette.swift
//  Sumi
//
//  The hover label is tinted by the current space's accent: a light wash on the
//  plate, a stronger one on the shortcut chips, with text shaded from whatever
//  fill it lands on so both stay readable in either chrome scheme.
//

import AppKit
import SwiftUI

struct SpaceHoverLabelPalette: Equatable {
    let surface: Color
    let surfaceBorder: Color
    let chipFill: Color
    let chipBorder: Color
    let titleText: Color
    let chipText: Color

    /// How much accent the plate takes from the opaque chrome base.
    static let surfaceAccentBlend: CGFloat = 0.20
    /// How much accent the shortcut chips take. Chips read as raised because
    /// they carry more accent than the plate they sit on.
    static let chipAccentBlend: CGFloat = 0.40
    /// Keeps the chip's fill light but pushes its hue clearly past the plate, so
    /// the key reads as its own surface. Saturation is boosted after blending so
    /// light and dark chrome keep the same relative separation.
    static let chipSaturationMultiplier: CGFloat = 2
    /// WCAG AA for the label's small text.
    static let textContrastRatio: CGFloat = 4.5
    /// How far the key's bottom edge is pulled from its fill toward the glyph.
    static let chipBorderBlend: CGFloat = 0.22

    @MainActor
    static func make(tokens: ChromeThemeTokens) -> Self {
        make(base: tokens.commandPaletteBackground, accent: tokens.accent)
    }

    @MainActor
    static func make(base: Color, accent: Color) -> Self {
        let surface = base.mixed(with: accent, amount: surfaceAccentBlend)
        let surfaceText = readableText(on: surface)
        let chipFill = base
            .mixed(with: accent, amount: chipAccentBlend)
            .multiplyingSaturation(by: chipSaturationMultiplier)
        let chipText = accentText(on: chipFill, accent: accent)
        return Self(
            surface: surface,
            surfaceBorder: surface.mixed(
                with: accentText(on: surface, accent: accent),
                amount: surfaceBorderBlend
            ),
            chipFill: chipFill,
            // A darker shade of the fill toward the glyph, shown only as the key's
            // bottom edge so the chip reads as a physical key without a full frame.
            chipBorder: chipFill.mixed(with: chipText, amount: chipBorderBlend),
            // The name reads as body text; the chips are the accent's own voice,
            // which is what makes them look like keys rather than more label.
            titleText: surfaceText,
            chipText: chipText
        )
    }

    /// A shade of the fill itself, so the text keeps the accent's hue instead of
    /// falling back to flat black or white.
    @MainActor
    private static func readableText(on fill: Color) -> Color {
        ThemeContrastResolver.contrastingShade(of: fill, targetRatio: textContrastRatio)
            ?? ThemeContrastResolver.preferredForeground(on: fill)
    }

    /// The accent at full saturation, pushed away from `fill` only as far as
    /// legibility demands — so a pale accent still reads as its own colour
    /// rather than collapsing to grey.
    @MainActor
    private static func accentText(on fill: Color, accent: Color) -> Color {
        let target = Double(textContrastRatio)
        let direction: Color = fill.relativeLuminance > 0.5 ? .black : .white

        var blend: CGFloat = 0
        while blend <= 1 {
            let candidate = accent.mixed(with: direction, amount: blend)
            if candidate.contrastRatio(with: fill) >= target {
                return candidate
            }
            blend += accentTextBlendStep
        }
        return readableText(on: fill)
    }

    private static let accentTextBlendStep: CGFloat = 0.05
    private static let surfaceBorderBlend: CGFloat = 0.14
}

private extension Color {
    func multiplyingSaturation(by multiplier: CGFloat) -> Color {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )
        return Color(
            hue: hue,
            saturation: min(saturation * multiplier, 1),
            brightness: brightness,
            opacity: alpha
        )
    }
}
