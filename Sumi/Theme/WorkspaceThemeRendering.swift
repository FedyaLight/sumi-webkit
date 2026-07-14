import AppKit
import Foundation
import SumiDomain
import SwiftUI

extension WorkspaceThemeColorAlgorithm {
    var displayName: String {
        switch self {
        case .floating:
            return "Free"
        case .complementary:
            return "Complementary"
        case .splitComplementary:
            return "Split Complementary"
        case .analogous:
            return "Analogous"
        case .triadic:
            return "Triadic"
        }
    }
}

extension WorkspaceThemeColor {
    init(
        id: UUID = UUID(),
        hex: String,
        isCustom: Bool = false,
        isPrimary: Bool = false,
        algorithm: WorkspaceThemeColorAlgorithm = .floating,
        lightness: Double? = nil,
        position: WorkspaceThemePosition,
        type: WorkspaceThemeColorType = .explicitLightness
    ) {
        self.init(
            id: id,
            hex: hex,
            isCustom: isCustom,
            isPrimary: isPrimary,
            algorithm: algorithm,
            lightness: lightness ?? Self.defaultLightness(for: hex),
            position: position,
            type: type
        )
    }

    var color: Color {
        Color(hex: hex)
    }

    static func defaultLightness(for hex: String) -> Double {
        NSColor(Color(hex: hex)).themePerceivedLightness
    }
}

struct WorkspaceGradientStop: Identifiable, Hashable, Sendable {
    var id: UUID
    var hex: String
    var location: Double
    var position: WorkspaceThemePosition

    init(id: UUID, hex: String, location: Double, position: WorkspaceThemePosition) {
        self.id = id
        self.hex = WorkspaceThemeColor.normalizedHex(hex)
        self.location = min(max(location, 0), 1)
        self.position = position
    }
}

struct WorkspaceResolvedGradient: Hashable, Sendable {
    static let maxStops = WorkspaceGradientTheme.maximumColorCount
    static let defaultPrimaryHex = WorkspaceGradientTheme.defaultPrimaryHex

    var angle: Double
    var stops: [WorkspaceGradientStop]
    var texture: Double
    var opacity: Double

    init(angle: Double, stops: [WorkspaceGradientStop], texture: Double, opacity: Double) {
        self.angle = Self.normalizedAngle(angle)
        self.stops = Array(stops.prefix(Self.maxStops))
        self.texture = min(max(texture, 0), 1)
        self.opacity = min(max(opacity, 0), 1)
    }

    static let `default` = WorkspaceResolvedGradient(
        angle: 225,
        stops: [
            WorkspaceGradientStop(
                id: UUID(),
                hex: defaultPrimaryHex,
                location: 0,
                position: .monochrome
            ),
        ],
        texture: 1.0 / 16.0,
        opacity: 0.62
    )

    static let incognito = WorkspaceResolvedGradient(
        angle: 180,
        stops: [
            WorkspaceGradientStop(
                id: UUID(),
                hex: "#1C1C1E",
                location: 0,
                position: .topLeft
            ),
            WorkspaceGradientStop(
                id: UUID(),
                hex: "#2C2C2E",
                location: 1,
                position: .bottom
            ),
        ],
        texture: 0,
        opacity: 1
    )

    var sortedStops: [WorkspaceGradientStop] {
        guard stops.count > 1 else { return stops }
        return stops.sorted { $0.location < $1.location }
    }

    var primaryColorHex: String {
        sortedStops.first?.hex ?? WorkspaceGradientTheme.accentHex()
    }

    var primaryColor: Color {
        Color(hex: primaryColorHex)
    }

    func visuallyEquals(
        _ other: WorkspaceResolvedGradient,
        angleEpsilon: Double = 0.5,
        textureEpsilon: Double = 0.01,
        opacityEpsilon: Double = 0.01
    ) -> Bool {
        let angleDiff = abs(angle - other.angle).truncatingRemainder(dividingBy: 360)
        let angleEqual = angleDiff < angleEpsilon || abs(angleDiff - 360) < angleEpsilon
        guard angleEqual,
              abs(texture - other.texture) <= textureEpsilon,
              abs(opacity - other.opacity) <= opacityEpsilon
        else {
            return false
        }

        let lhs = sortedStops
        let rhs = other.sortedStops
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.hex.caseInsensitiveCompare(right.hex) == .orderedSame
                && abs(left.location - right.location) <= 1e-4
                && abs(left.position.x - right.position.x) <= 1e-4
                && abs(left.position.y - right.position.y) <= 1e-4
        }
    }

    func interpolated(to other: WorkspaceResolvedGradient, progress: Double) -> WorkspaceResolvedGradient {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return self }
        guard clamped < 1 else { return other }

        let leftStops = sortedStops
        let rightStops = other.sortedStops
        let stopCount = max(leftStops.count, rightStops.count, 1)
        let blendedStops = (0..<stopCount).map { index in
            let left = Self.stop(at: index, in: leftStops)
            let right = Self.stop(at: index, in: rightStops)
            return WorkspaceGradientStop(
                id: left?.id ?? right?.id ?? UUID(),
                hex: Self.blendedHex(
                    left?.hex ?? right?.hex ?? Self.defaultPrimaryHex,
                    right?.hex ?? left?.hex ?? Self.defaultPrimaryHex,
                    amount: clamped
                ),
                location: Self.interpolate(
                    left?.location ?? right?.location ?? 0,
                    right?.location ?? left?.location ?? 0,
                    amount: clamped
                ),
                position: WorkspaceThemePosition(
                    x: Self.interpolate(
                        left?.position.x ?? right?.position.x ?? WorkspaceThemePosition.monochrome.x,
                        right?.position.x ?? left?.position.x ?? WorkspaceThemePosition.monochrome.x,
                        amount: clamped
                    ),
                    y: Self.interpolate(
                        left?.position.y ?? right?.position.y ?? WorkspaceThemePosition.monochrome.y,
                        right?.position.y ?? left?.position.y ?? WorkspaceThemePosition.monochrome.y,
                        amount: clamped
                    )
                )
            )
        }

        return WorkspaceResolvedGradient(
            angle: Self.interpolateAngle(angle, other.angle, amount: clamped),
            stops: blendedStops,
            texture: Self.interpolate(texture, other.texture, amount: clamped),
            opacity: Self.interpolate(opacity, other.opacity, amount: clamped)
        )
    }

    private static func normalizedAngle(_ value: Double) -> Double {
        var normalized = value.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        return normalized
    }

    private static func stop(
        at index: Int,
        in stops: [WorkspaceGradientStop]
    ) -> WorkspaceGradientStop? {
        guard !stops.isEmpty else { return nil }
        return stops[min(index, stops.count - 1)]
    }

    private static func interpolate(_ first: Double, _ second: Double, amount: Double) -> Double {
        first + (second - first) * amount
    }

    private static func interpolateAngle(_ first: Double, _ second: Double, amount: Double) -> Double {
        var delta = (second - first).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return normalizedAngle(first + delta * amount)
    }

    private static func blendedHex(_ first: String, _ second: String, amount: Double) -> String {
        guard let left = rgbComponents(for: first),
              let right = rgbComponents(for: second)
        else {
            return amount < 0.5
                ? WorkspaceThemeColor.normalizedHex(first)
                : WorkspaceThemeColor.normalizedHex(second)
        }

        let red = Int(round(interpolate(Double(left.red), Double(right.red), amount: amount)))
        let green = Int(round(interpolate(Double(left.green), Double(right.green), amount: amount)))
        let blue = Int(round(interpolate(Double(left.blue), Double(right.blue), amount: amount)))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func rgbComponents(for hex: String) -> (red: Int, green: Int, blue: Int)? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard rawValue.count == 6,
              let value = Int(rawValue, radix: 16)
        else {
            return nil
        }

        return (
            red: (value >> 16) & 0xFF,
            green: (value >> 8) & 0xFF,
            blue: value & 0xFF
        )
    }
}

extension WorkspaceGradientTheme {
    static let customChromeThemeDisableThreshold: Double = 0.02
    static let customChromeThemeMaterialHandoffStartThreshold: Double = 0.25
    static let customChromeThemeOpaqueThreshold: Double = 0.30
    static let customChromeTextureEnableThreshold: Double = 0.31

    var primaryColorHex: String {
        normalizedColors.first?.hex ?? Self.accentHex()
    }

    var primaryColor: Color {
        Color(hex: primaryColorHex)
    }

    var renderGradient: WorkspaceResolvedGradient {
        let renderColors = normalizedColors
        let stops = zip(renderColors, Self.locations(for: renderColors.count)).map { item, location in
            WorkspaceGradientStop(
                id: item.id,
                hex: item.hex,
                location: location,
                position: item.position
            )
        }
        return WorkspaceResolvedGradient(
            angle: Self.renderAngle(for: renderColors),
            stops: stops,
            texture: texture,
            opacity: opacity
        )
    }

    var customChromeThemeIntensity: Double {
        if opacity < Self.customChromeThemeDisableThreshold { return 0 }
        if opacity >= Self.customChromeThemeMaterialHandoffStartThreshold {
            let start = Self.customChromeThemeMaterialHandoffStartThreshold
            return start + (1 - start) * customChromeThemeMaterialHandoffProgress
        }
        return opacity
    }

    var usesCustomChromeTheme: Bool {
        customChromeThemeIntensity > 0
    }

    var rendersOpaqueCustomChromeTheme: Bool {
        customChromeThemeIntensity >= 1
    }

    var customChromeThemeSaturation: Double {
        if !rendersOpaqueCustomChromeTheme {
            return 1 - (1 - opacity) * customChromeThemeMaterialHandoffProgress
        }
        return min(max(opacity, 0), 1)
    }

    var allowsCustomChromeTexture: Bool {
        opacity >= Self.customChromeTextureEnableThreshold
    }

    var customChromeThemeNativeMaterialOpacity: Double {
        guard opacity >= Self.customChromeThemeMaterialHandoffStartThreshold else { return 1 }
        return 1 - customChromeThemeMaterialHandoffProgress
    }

    var keepsNativeMaterialDuringHandoff: Bool {
        opacity < Self.customChromeTextureEnableThreshold
    }

    var customChromeThemeMaterialHandoffProgress: Double {
        let start = Self.customChromeThemeMaterialHandoffStartThreshold
        let end = Self.customChromeThemeOpaqueThreshold
        guard opacity >= start, end > start else { return 0 }
        return min(max((opacity - start) / (end - start), 0), 1)
    }

    static func accentHex() -> String {
        let accent = NSColor.controlAccentColor
        guard let rgb = accent.usingColorSpace(.sRGB) else { return "#007AFF" }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }

    private static func locations(for count: Int) -> [Double] {
        switch count {
        case 0: return []
        case 1: return [0]
        case 2: return [0, 1]
        default: return [0, 0.5, 1]
        }
    }

    private static func renderAngle(for colors: [WorkspaceThemeColor]) -> Double {
        guard colors.count > 1,
              let first = colors.first,
              let last = colors.last
        else {
            return 225
        }

        let dx = last.position.x - first.position.x
        let dy = last.position.y - first.position.y
        guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else { return 225 }

        var angle = Angle(radians: atan2(dy, dx)).degrees
        if angle < 0 { angle += 360 }
        return angle
    }
}

extension WorkspaceTheme {
    var gradient: WorkspaceResolvedGradient { gradientTheme.renderGradient }

    func interpolated(to other: WorkspaceTheme, progress: Double) -> WorkspaceTheme {
        let clamped = min(max(progress, 0), 1)
        return clamped < 0.5 ? self : other
    }

    func visuallyEquals(_ other: WorkspaceTheme) -> Bool {
        gradient.visuallyEquals(other.gradient)
            && usesExplicitColorScheme == other.usesExplicitColorScheme
    }
}

extension NSColor {
    var themePerceivedLightness: Double {
        let rgb = usingColorSpace(.sRGB) ?? self
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return Double((max(red, green, blue) + min(red, green, blue)) / 2)
    }
}
