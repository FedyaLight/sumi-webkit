import SwiftUI

enum SumiBoostColorPreview {
    /// Mirrors the Zen reference editor (ZenBoostsEditor.mjs `updateDot`):
    /// the dots visualize the *input* hue + saturation picked on the wheel
    /// (saturation comes from the radial distance), with fixed lightness.
    /// They are not a literal preview of the page filter; the advanced
    /// brightness/contrast/saturation sliders drive the page filter on top.
    static func primaryDotColor(for data: SumiBoostData) -> Color {
        hslColor(
            hueDegrees: data.dotAngleDeg,
            saturation: clamped(data.dotDistance, lower: 0.05, upper: 1),
            lightness: 0.55
        )
    }

    static func backgroundDotColor(for data: SumiBoostData) -> Color {
        // Same hue/saturation formula the CSS builder uses for the page
        // background, so the secondary dot tells the truth about the bg color.
        hslColor(
            hueDegrees: data.dotAngleDeg + data.secondaryDotAngleDegDelta,
            saturation: clamped(data.dotDistance, lower: 0.05, upper: 1),
            lightness: 0.2
        )
    }

    private static func hslColor(
        hueDegrees: Double,
        saturation: Double,
        lightness: Double
    ) -> Color {
        let hue = normalizedDegrees(hueDegrees) / 360
        let saturation = clamped(saturation, lower: 0, upper: 1)
        let lightness = clamped(lightness, lower: 0, upper: 1)

        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let huePrime = hue * 6
        let x = chroma * (1 - abs(huePrime.truncatingRemainder(dividingBy: 2) - 1))
        let match = lightness - chroma / 2

        let rgb: (Double, Double, Double)
        switch huePrime {
        case 0..<1:
            rgb = (chroma, x, 0)
        case 1..<2:
            rgb = (x, chroma, 0)
        case 2..<3:
            rgb = (0, chroma, x)
        case 3..<4:
            rgb = (0, x, chroma)
        case 4..<5:
            rgb = (x, 0, chroma)
        default:
            rgb = (chroma, 0, x)
        }

        return Color(
            red: rgb.0 + match,
            green: rgb.1 + match,
            blue: rgb.2 + match,
            opacity: 1
        )
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
