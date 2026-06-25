import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum WorkspaceThemeColorAlgorithm: String, CaseIterable, Identifiable, Codable, Sendable {
    case floating = "floating"
    case complementary = "complementary"
    case splitComplementary = "splitComplementary"
    case analogous = "analogous"
    case triadic = "triadic"

    var id: String { rawValue }

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

enum WorkspaceThemeColorType: String, Codable, CaseIterable, Sendable {
    case explicitLightness = "explicit-lightness"
    case explicitBlackWhite = "explicit-black-white"
}

struct WorkspaceThemePosition: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    static let topLeft = WorkspaceThemePosition(x: 0.2, y: 0.24)
    static let bottom = WorkspaceThemePosition(x: 0.5, y: 0.82)
    static let monochrome = WorkspaceThemePosition(x: 0.66, y: 0.5)
}

struct WorkspaceThemeColor: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var hex: String
    var isCustom: Bool
    var isPrimary: Bool
    var algorithm: WorkspaceThemeColorAlgorithm
    var lightness: Double
    var position: WorkspaceThemePosition
    var type: WorkspaceThemeColorType

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
        self.id = id
        self.hex = hex.normalizedThemeHex()
        self.isCustom = isCustom
        self.isPrimary = isPrimary
        self.algorithm = algorithm
        self.lightness = min(max(lightness ?? WorkspaceThemeColor.defaultLightness(for: hex), 0), 1)
        self.position = position
        self.type = type
    }

    var color: Color {
        Color(hex: hex)
    }

    static func defaultLightness(for hex: String) -> Double {
        #if canImport(AppKit)
        return NSColor(Color(hex: hex)).themePerceivedLightness
        #else
        return 0.5
        #endif
    }
}

struct WorkspaceGradientStop: Identifiable, Hashable, Sendable {
    var id: UUID
    var hex: String
    var location: Double
    var position: WorkspaceThemePosition

    init(id: UUID, hex: String, location: Double, position: WorkspaceThemePosition) {
        self.id = id
        self.hex = hex.normalizedThemeHex()
        self.location = min(max(location, 0), 1)
        self.position = position
    }
}

struct WorkspaceResolvedGradient: Hashable, Sendable {
    static let maxStops = 3
    static let defaultPrimaryHex = "#F4EFDF"

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
            )
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
            )
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
            let fallbackID = left?.id ?? right?.id ?? UUID()
            return WorkspaceGradientStop(
                id: fallbackID,
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
            return amount < 0.5 ? first.normalizedThemeHex() : second.normalizedThemeHex()
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

struct WorkspaceGradientTheme: Codable, Hashable, Sendable {
    static let minimumOpacity: Double = 0
    static let maximumOpacity: Double = 1
    static let textureSteps: Double = 16
    static let customChromeThemeDisableThreshold: Double = 0.02
    static let customChromeThemeMaterialHandoffStartThreshold: Double = 0.25
    static let customChromeThemeOpaqueThreshold: Double = 0.30
    static let customChromeTextureEnableThreshold: Double = 0.31

    var type: String
    var colors: [WorkspaceThemeColor]
    var opacity: Double
    var texture: Double

    init(
        type: String = "gradient",
        colors: [WorkspaceThemeColor],
        opacity: Double = 0.64,
        texture: Double = 0.18
    ) {
        self.type = type
        self.colors = WorkspaceGradientTheme.normalized(colors)
        self.opacity = WorkspaceGradientTheme.clampOpacity(opacity)
        self.texture = WorkspaceGradientTheme.quantizeTexture(texture)
    }

    static var `default`: WorkspaceGradientTheme {
        WorkspaceGradientTheme(
            colors: [
                WorkspaceThemeColor(
                    hex: WorkspaceResolvedGradient.defaultPrimaryHex,
                    isPrimary: true,
                    position: .monochrome
                )
            ],
            opacity: 0.62,
            texture: 1.0 / 16.0
        )
    }

    static var incognito: WorkspaceGradientTheme {
        WorkspaceGradientTheme(
            colors: [
                WorkspaceThemeColor(
                    hex: "#1C1C1E",
                    isPrimary: true,
                    algorithm: .analogous,
                    position: .topLeft
                ),
                WorkspaceThemeColor(
                    hex: "#2C2C2E",
                    algorithm: .analogous,
                    position: .bottom
                )
            ],
            opacity: 1,
            texture: 0
        )
    }

    var primaryColorHex: String {
        normalizedColors.first?.hex ?? WorkspaceGradientTheme.accentHex()
    }

    var primaryColor: Color {
        Color(hex: primaryColorHex)
    }

    var normalizedColors: [WorkspaceThemeColor] {
        WorkspaceGradientTheme.normalized(colors)
    }

    var algorithm: WorkspaceThemeColorAlgorithm {
        normalizedColors.first?.algorithm ?? .floating
    }

    var renderGradient: WorkspaceResolvedGradient {
        let renderColors = normalizedColors
        let locations = WorkspaceGradientTheme.locations(for: renderColors.count)
        let stops = zip(renderColors, locations).map { pair in
            let (item, location) = pair
            return WorkspaceGradientStop(
                id: item.id,
                hex: item.hex,
                location: location,
                position: item.position
            )
        }

        return WorkspaceResolvedGradient(
            angle: WorkspaceGradientTheme.renderAngle(for: renderColors),
            stops: stops,
            texture: texture,
            opacity: opacity
        )
    }

    mutating func updateTexture(_ value: Double) {
        texture = WorkspaceGradientTheme.quantizeTexture(value)
    }

    mutating func updateOpacity(_ value: Double) {
        opacity = WorkspaceGradientTheme.clampOpacity(value)
    }

    var customChromeThemeIntensity: Double {
        if opacity < WorkspaceGradientTheme.customChromeThemeDisableThreshold {
            return 0
        }
        if opacity >= WorkspaceGradientTheme.customChromeThemeMaterialHandoffStartThreshold {
            let progress = customChromeThemeMaterialHandoffProgress
            let start = WorkspaceGradientTheme.customChromeThemeMaterialHandoffStartThreshold
            return start + (1 - start) * progress
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
            let progress = customChromeThemeMaterialHandoffProgress
            return 1 - (1 - opacity) * progress
        }

        return min(max(opacity, 0), 1)
    }

    var allowsCustomChromeTexture: Bool {
        opacity >= WorkspaceGradientTheme.customChromeTextureEnableThreshold
    }

    var customChromeThemeNativeMaterialOpacity: Double {
        guard opacity >= WorkspaceGradientTheme.customChromeThemeMaterialHandoffStartThreshold else {
            return 1
        }
        return 1 - customChromeThemeMaterialHandoffProgress
    }

    var keepsNativeMaterialDuringHandoff: Bool {
        opacity < WorkspaceGradientTheme.customChromeTextureEnableThreshold
    }

    var customChromeThemeMaterialHandoffProgress: Double {
        let start = WorkspaceGradientTheme.customChromeThemeMaterialHandoffStartThreshold
        let end = WorkspaceGradientTheme.customChromeThemeOpaqueThreshold
        guard opacity >= start, end > start else { return 0 }
        return min(max((opacity - start) / (end - start), 0), 1)
    }

    mutating func replaceColors(
        _ updatedColors: [WorkspaceThemeColor],
        algorithm: WorkspaceThemeColorAlgorithm? = nil
    ) {
        colors = WorkspaceGradientTheme.normalized(
            updatedColors.enumerated().map { index, color in
                var copy = color
                if let algorithm {
                    copy.algorithm = algorithm
                } else if index == 0 {
                    copy.algorithm = color.algorithm
                }
                return copy
            }
        )
    }

    private static func normalized(_ colors: [WorkspaceThemeColor]) -> [WorkspaceThemeColor] {
        let limited = Array(colors.prefix(WorkspaceResolvedGradient.maxStops))
        guard !limited.isEmpty else {
            return []
        }

        return limited.enumerated().map { index, color in
            var copy = color
            copy.hex = color.hex.normalizedThemeHex()
            copy.isPrimary = index == 0
            copy.lightness = min(max(color.lightness, 0), 1)
            return copy
        }
    }

    private static func locations(for count: Int) -> [Double] {
        switch count {
        case 0:
            return []
        case 1:
            return [0.0]
        case 2:
            return [0.0, 1.0]
        default:
            return [0.0, 0.5, 1.0]
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
        guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else {
            return 225
        }

        var angle = Angle(radians: atan2(dy, dx)).degrees
        if angle < 0 {
            angle += 360
        }
        return angle
    }

    private static func clampOpacity(_ value: Double) -> Double {
        min(max(value, minimumOpacity), maximumOpacity)
    }

    private static func quantizeTexture(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        let quantized = (clamped * textureSteps).rounded() / textureSteps
        return quantized >= 1 ? 0 : quantized
    }

    static func accentHex() -> String {
        #if canImport(AppKit)
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
        #else
        return "#007AFF"
        #endif
    }
}

struct WorkspaceTheme: Codable, Hashable, Sendable {
    var gradientTheme: WorkspaceGradientTheme
    var usesExplicitColorScheme: Bool

    enum CodingKeys: String, CodingKey {
        case gradientTheme
        case usesExplicitColorScheme
    }

    init(
        gradientTheme: WorkspaceGradientTheme = .default,
        usesExplicitColorScheme: Bool = true
    ) {
        self.gradientTheme = gradientTheme
        self.usesExplicitColorScheme = usesExplicitColorScheme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let gradientTheme = try container.decode(WorkspaceGradientTheme.self, forKey: .gradientTheme)
        self.gradientTheme = gradientTheme
        self.usesExplicitColorScheme = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesExplicitColorScheme
        ) ?? !gradientTheme.normalizedColors.isEmpty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gradientTheme, forKey: .gradientTheme)
        try container.encode(usesExplicitColorScheme, forKey: .usesExplicitColorScheme)
    }

    static var `default`: WorkspaceTheme {
        WorkspaceTheme(
            gradientTheme: .default,
            usesExplicitColorScheme: false
        )
    }

    static var incognito: WorkspaceTheme {
        WorkspaceTheme(
            gradientTheme: .incognito,
            usesExplicitColorScheme: true
        )
    }

    var gradient: WorkspaceResolvedGradient { gradientTheme.renderGradient }

    var encoded: Data? {
        let encoder = JSONEncoder()
        do {
            return try encoder.encode(self)
        } catch {
            RuntimeDiagnostics.debug(
                "WorkspaceTheme encoding failed: \(error)",
                category: "WorkspaceTheme"
            )
            return nil
        }
    }

    static func decode(_ data: Data) -> WorkspaceTheme? {
        guard !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        if let theme = try? decoder.decode(WorkspaceTheme.self, from: data) {
            return theme
        }
        return nil
    }

    func interpolated(to other: WorkspaceTheme, progress: Double) -> WorkspaceTheme {
        let clamped = min(max(progress, 0), 1)
        return clamped < 0.5 ? self : other
    }

    func visuallyEquals(_ other: WorkspaceTheme) -> Bool {
        gradient.visuallyEquals(other.gradient)
            && usesExplicitColorScheme == other.usesExplicitColorScheme
    }
}

private extension String {
    func normalizedThemeHex() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return "#\(trimmed.uppercased())" }
        return trimmed.uppercased()
    }
}

#if canImport(AppKit)
extension NSColor {
    var themePerceivedLightness: Double {
        let rgb = usingColorSpace(.sRGB) ?? self
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        return Double((maxValue + minValue) / 2.0)
    }
}
#endif
