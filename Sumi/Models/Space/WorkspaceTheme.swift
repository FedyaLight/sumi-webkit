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
    static let topRight = WorkspaceThemePosition(x: 0.8, y: 0.24)
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

struct WorkspaceGradientTheme: Codable, Hashable, Sendable {
    static let minimumOpacity: Double = 0.30
    static let maximumOpacity: Double = 0.90
    static let textureSteps: Double = 16

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

    init(
        renderGradient: SpaceGradient,
        preserving previous: WorkspaceGradientTheme? = nil
    ) {
        let nodes = Array(renderGradient.sortedNodes.prefix(3))
        let fallbackPositions = WorkspaceGradientTheme.defaultPositions(for: nodes.count)

        self.type = "gradient"
        self.opacity = WorkspaceGradientTheme.clampOpacity(renderGradient.opacity)
        self.texture = WorkspaceGradientTheme.quantizeTexture(renderGradient.grain)
        self.colors = WorkspaceGradientTheme.normalized(
            nodes.enumerated().map { index, node in
                let previousColor = previous?.colors.first(where: { $0.id == node.id })
                let position = WorkspaceThemePosition(
                    x: node.xPosition ?? previousColor?.position.x ?? fallbackPositions[index].x,
                    y: node.yPosition ?? previousColor?.position.y ?? fallbackPositions[index].y
                )
                return WorkspaceThemeColor(
                    id: node.id,
                    hex: node.colorHex,
                    isCustom: previousColor?.isCustom ?? false,
                    isPrimary: index == 0,
                    algorithm: previousColor?.algorithm ?? (nodes.count > 1 ? .analogous : .floating),
                    lightness: previousColor?.lightness ?? WorkspaceThemeColor.defaultLightness(for: node.colorHex),
                    position: position,
                    type: previousColor?.type ?? .explicitLightness
                )
            }
        )
    }

    static var `default`: WorkspaceGradientTheme {
        WorkspaceGradientTheme(renderGradient: .default)
    }

    var primaryColorHex: String {
        normalizedColors.first?.hex ?? SpaceGradient.default.primaryColorHex
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

    var renderGradient: SpaceGradient {
        let renderColors = normalizedColors
        let locations = WorkspaceGradientTheme.locations(for: renderColors.count)
        let nodes = zip(renderColors, locations).map { pair in
            let (item, location) = pair
            return GradientNode(
                id: item.id,
                colorHex: item.hex,
                location: location,
                xPosition: item.position.x,
                yPosition: item.position.y
            )
        }

        return SpaceGradient(
            angle: WorkspaceGradientTheme.renderAngle(for: renderColors),
            nodes: nodes,
            grain: texture,
            opacity: opacity
        )
    }

    mutating func updateTexture(_ value: Double) {
        texture = WorkspaceGradientTheme.quantizeTexture(value)
    }

    mutating func updateOpacity(_ value: Double) {
        opacity = WorkspaceGradientTheme.clampOpacity(value)
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
        let limited = Array(colors.prefix(3))
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

    private static func defaultPositions(for count: Int) -> [WorkspaceThemePosition] {
        switch count {
        case 0:
            return [WorkspaceThemePosition.monochrome]
        case 1:
            return [WorkspaceThemePosition.monochrome]
        case 2:
            return [.topLeft, .bottom]
        default:
            return [.topLeft, .topRight, .bottom]
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
}

struct WorkspaceTheme: Codable, Hashable, Sendable {
    var gradientTheme: WorkspaceGradientTheme

    init(gradientTheme: WorkspaceGradientTheme = .default) {
        self.gradientTheme = gradientTheme
    }

    init(gradient: SpaceGradient = .default) {
        self.init(
            gradientTheme: WorkspaceGradientTheme(renderGradient: gradient)
        )
    }

    static var `default`: WorkspaceTheme {
        WorkspaceTheme(gradientTheme: .default)
    }

    static var incognito: WorkspaceTheme {
        WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(renderGradient: .incognito)
        )
    }

    var gradient: SpaceGradient {
        get { gradientTheme.renderGradient }
        set { gradientTheme = WorkspaceGradientTheme(renderGradient: newValue, preserving: gradientTheme) }
    }

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
        return WorkspaceTheme(
            gradient: gradient.interpolated(to: other.gradient, progress: clamped)
        )
    }

    func visuallyEquals(_ other: WorkspaceTheme) -> Bool {
        gradient.visuallyEquals(other.gradient)
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
private extension NSColor {
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
