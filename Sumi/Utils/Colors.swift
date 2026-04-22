import SwiftUI
import Foundation
#if canImport(AppKit)
import AppKit
#endif

extension Color {
    func overlaying(_ overlay: Color) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .clear
        let top = NSColor(overlay).usingColorSpace(.sRGB) ?? .clear

        var br: CGFloat = 0
        var bg: CGFloat = 0
        var bb: CGFloat = 0
        var ba: CGFloat = 0
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)

        var tr: CGFloat = 0
        var tg: CGFloat = 0
        var tb: CGFloat = 0
        var ta: CGFloat = 0
        top.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)

        let outA = ta + ba * (1 - ta)
        guard outA > 0.0001 else { return .clear }

        let outR = (tr * ta + br * ba * (1 - ta)) / outA
        let outG = (tg * ta + bg * ba * (1 - ta)) / outA
        let outB = (tb * ta + bb * ba * (1 - ta)) / outA

        return Color(.sRGB, red: outR, green: outG, blue: outB, opacity: outA)
    }

    func mixed(with other: Color, amount: CGFloat) -> Color {
        let ratio = max(0, min(1, amount))
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .clear
        let target = NSColor(other).usingColorSpace(.sRGB) ?? .clear

        var br: CGFloat = 0
        var bg: CGFloat = 0
        var bb: CGFloat = 0
        var ba: CGFloat = 0
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)

        var tr: CGFloat = 0
        var tg: CGFloat = 0
        var tb: CGFloat = 0
        var ta: CGFloat = 0
        target.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)

        return Color(
            .sRGB,
            red: br * (1 - ratio) + tr * ratio,
            green: bg * (1 - ratio) + tg * ratio,
            blue: bb * (1 - ratio) + tb * ratio,
            opacity: ba * (1 - ratio) + ta * ratio
        )
    }

    func mix(with other: Color, by amount: CGFloat) -> Color {
        mixed(with: other, amount: amount)
    }

    var sRGBComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let resolved = NSColor(self).usingColorSpace(.sRGB) ?? .clear
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }

    var relativeLuminance: Double {
        let components = sRGBComponents
        let values = [components.red, components.green, components.blue].map { component -> Double in
            let normalized = Double(component)
            return normalized <= 0.03928
                ? normalized / 12.92
                : pow((normalized + 0.055) / 1.055, 2.4)
        }

        return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
    }

    func contrastRatio(with other: Color) -> Double {
        let lhs = relativeLuminance
        let rhs = other.relativeLuminance
        let brightest = max(lhs, rhs)
        let darkest = min(lhs, rhs)
        return (brightest + 0.05) / (darkest + 0.05)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (
                255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17
            )
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (
                int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF
            )
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHexString(includeAlpha: Bool = false) -> String? {
        let ns = NSColor(self)
        return ns.toHexString(includeAlpha: includeAlpha)
    }
    
}

extension NSColor {
    func toHexString(includeAlpha: Bool = false) -> String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        if includeAlpha {
            let ai = Int(round(a * 255))
            return String(format: "#%02X%02X%02X%02X", ai, ri, gi, bi)
        } else {
            return String(format: "#%02X%02X%02X", ri, gi, bi)
        }
    }
}
