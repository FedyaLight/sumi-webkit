import Foundation

public enum WorkspaceThemeColorAlgorithm: String, CaseIterable, Identifiable, Codable, Sendable {
    case floating = "floating"
    case complementary = "complementary"
    case splitComplementary = "splitComplementary"
    case analogous = "analogous"
    case triadic = "triadic"

    public var id: String { rawValue }
}

public enum WorkspaceThemeColorType: String, Codable, CaseIterable, Sendable {
    case explicitLightness = "explicit-lightness"
    case explicitBlackWhite = "explicit-black-white"
}

public struct WorkspaceThemePosition: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    public static let topLeft = WorkspaceThemePosition(x: 0.2, y: 0.24)
    public static let bottom = WorkspaceThemePosition(x: 0.5, y: 0.82)
    public static let monochrome = WorkspaceThemePosition(x: 0.66, y: 0.5)
}

public struct WorkspaceThemeColor: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var hex: String
    public var isCustom: Bool
    public var isPrimary: Bool
    public var algorithm: WorkspaceThemeColorAlgorithm
    public var lightness: Double
    public var position: WorkspaceThemePosition
    public var type: WorkspaceThemeColorType

    public init(
        id: UUID = UUID(),
        hex: String,
        isCustom: Bool = false,
        isPrimary: Bool = false,
        algorithm: WorkspaceThemeColorAlgorithm = .floating,
        lightness: Double,
        position: WorkspaceThemePosition,
        type: WorkspaceThemeColorType = .explicitLightness
    ) {
        self.id = id
        self.hex = Self.normalizedHex(hex)
        self.isCustom = isCustom
        self.isPrimary = isPrimary
        self.algorithm = algorithm
        self.lightness = min(max(lightness, 0), 1)
        self.position = position
        self.type = type
    }

    public static func normalizedHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return "#\(trimmed.uppercased())" }
        return trimmed.uppercased()
    }
}

public struct WorkspaceGradientTheme: Codable, Hashable, Sendable {
    public static let minimumOpacity: Double = 0
    public static let maximumOpacity: Double = 1
    public static let textureSteps: Double = 16
    public static let maximumColorCount = 3
    public static let defaultPrimaryHex = "#F4EFDF"

    public var type: String
    public var colors: [WorkspaceThemeColor]
    public var opacity: Double
    public var texture: Double

    public init(
        type: String = "gradient",
        colors: [WorkspaceThemeColor],
        opacity: Double = 0.64,
        texture: Double = 0.18
    ) {
        self.type = type
        self.colors = Self.normalized(colors)
        self.opacity = Self.clampOpacity(opacity)
        self.texture = Self.quantizeTexture(texture)
    }

    public static var `default`: WorkspaceGradientTheme {
        WorkspaceGradientTheme(
            colors: [
                WorkspaceThemeColor(
                    hex: defaultPrimaryHex,
                    isPrimary: true,
                    algorithm: .floating,
                    lightness: 0.90,
                    position: WorkspaceThemePosition(
                        x: 240.0 / 360.0,
                        y: 240.0 / 360.0
                    ),
                    type: .explicitLightness
                ),
            ],
            opacity: 0.62,
            texture: 0.08
        )
    }

    public static var incognito: WorkspaceGradientTheme {
        WorkspaceGradientTheme(
            colors: [
                WorkspaceThemeColor(
                    hex: "#1C1C1E",
                    isPrimary: true,
                    algorithm: .analogous,
                    lightness: 58.0 / 510.0,
                    position: .topLeft
                ),
                WorkspaceThemeColor(
                    hex: "#2C2C2E",
                    algorithm: .analogous,
                    lightness: 90.0 / 510.0,
                    position: .bottom
                ),
            ],
            opacity: 1,
            texture: 0
        )
    }

    public var normalizedColors: [WorkspaceThemeColor] {
        Self.normalized(colors)
    }

    public var algorithm: WorkspaceThemeColorAlgorithm {
        normalizedColors.first?.algorithm ?? .floating
    }

    public mutating func updateTexture(_ value: Double) {
        texture = Self.quantizeTexture(value)
    }

    public mutating func updateOpacity(_ value: Double) {
        opacity = Self.clampOpacity(value)
    }

    public mutating func replaceColors(
        _ updatedColors: [WorkspaceThemeColor],
        algorithm: WorkspaceThemeColorAlgorithm? = nil
    ) {
        colors = Self.normalized(
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
        let limited = Array(colors.prefix(maximumColorCount))
        guard !limited.isEmpty else { return [] }

        return limited.enumerated().map { index, color in
            var copy = color
            copy.hex = WorkspaceThemeColor.normalizedHex(color.hex)
            copy.isPrimary = index == 0
            copy.lightness = min(max(color.lightness, 0), 1)
            return copy
        }
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

public struct WorkspaceTheme: Codable, Hashable, Sendable {
    public var gradientTheme: WorkspaceGradientTheme
    public var usesExplicitColorScheme: Bool

    private enum CodingKeys: String, CodingKey {
        case gradientTheme
        case usesExplicitColorScheme
    }

    public init(
        gradientTheme: WorkspaceGradientTheme = .default,
        usesExplicitColorScheme: Bool = true
    ) {
        self.gradientTheme = gradientTheme
        self.usesExplicitColorScheme = usesExplicitColorScheme
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let gradientTheme = try container.decode(
            WorkspaceGradientTheme.self,
            forKey: .gradientTheme
        )
        let usesExplicitColorScheme = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesExplicitColorScheme
        ) ?? !gradientTheme.normalizedColors.isEmpty

        self.gradientTheme = gradientTheme
        self.usesExplicitColorScheme = usesExplicitColorScheme
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gradientTheme, forKey: .gradientTheme)
        try container.encode(usesExplicitColorScheme, forKey: .usesExplicitColorScheme)
    }

    public static var `default`: WorkspaceTheme {
        WorkspaceTheme(
            gradientTheme: .default,
            usesExplicitColorScheme: true
        )
    }

    public static var incognito: WorkspaceTheme {
        WorkspaceTheme(
            gradientTheme: .incognito,
            usesExplicitColorScheme: true
        )
    }
}
