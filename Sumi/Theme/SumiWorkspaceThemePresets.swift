import SwiftUI

struct SumiWorkspaceThemePreset: Identifiable, Hashable {
    let id: String
    let workspaceTheme: WorkspaceTheme

    static func single(
        _ group: String,
        _ index: Int,
        _ hex: String,
        position: WorkspaceThemePosition,
        opacity: Double,
        texture: Double,
        lightness: Double,
        type: WorkspaceThemeColorType = .explicitLightness
    ) -> SumiWorkspaceThemePreset {
        SumiWorkspaceThemePreset(
            id: "\(group)-\(index)",
            workspaceTheme: WorkspaceTheme(
                gradientTheme: WorkspaceGradientTheme(
                    colors: [
                        WorkspaceThemeColor(
                            hex: hex,
                            isPrimary: true,
                            algorithm: .floating,
                            lightness: lightness,
                            position: position,
                            type: type
                        )
                    ],
                    opacity: opacity,
                    texture: texture
                )
            )
        )
    }

    static func trio(
        _ group: String,
        _ index: Int,
        _ colors: [String],
        position: WorkspaceThemePosition,
        opacity: Double,
        texture: Double,
        lightness: Double
    ) -> SumiWorkspaceThemePreset {
        let resolvedPositions = analogousPositions(from: position)
        return SumiWorkspaceThemePreset(
            id: "\(group)-\(index)",
            workspaceTheme: WorkspaceTheme(
                gradientTheme: WorkspaceGradientTheme(
                    colors: zip(colors, resolvedPositions).enumerated().map { entry in
                        let index = entry.offset
                        let (hex, point) = entry.element
                        return WorkspaceThemeColor(
                            hex: hex,
                            isPrimary: index == 0,
                            algorithm: .analogous,
                            lightness: lightness,
                            position: point
                        )
                    },
                    opacity: opacity,
                    texture: texture
                )
            )
        )
    }

    private static func analogousPositions(from primary: WorkspaceThemePosition) -> [WorkspaceThemePosition] {
        let companionA = WorkspaceThemePosition(
            x: min(max(primary.x + 0.23, 0.12), 0.88),
            y: min(max(primary.y + 0.08, 0.12), 0.88)
        )
        let companionB = WorkspaceThemePosition(
            x: min(max(primary.x - 0.18, 0.12), 0.88),
            y: min(max(primary.y + 0.3, 0.12), 0.88)
        )
        return [primary, companionA, companionB]
    }
}

struct SumiWorkspaceThemePresetGroup: Identifiable, Hashable {
    let name: String
    let presets: [SumiWorkspaceThemePreset]

    var id: String { name }
}

enum SumiWorkspaceThemePresets {
    static let groups: [SumiWorkspaceThemePresetGroup] = [
        SumiWorkspaceThemePresetGroup(
            name: "Light Mono",
            presets: [
                .single("Light Mono", 1, "#F4EFDF", position: point(240, 240), opacity: 0.62, texture: 0.08, lightness: 0.90),
                .single("Light Mono", 2, "#F0B8CD", position: point(233, 157), opacity: 0.64, texture: 0.10, lightness: 0.80),
                .single("Light Mono", 3, "#E9C3E3", position: point(236, 111), opacity: 0.64, texture: 0.10, lightness: 0.80),
                .single("Light Mono", 4, "#DA7682", position: point(234, 173), opacity: 0.70, texture: 0.12, lightness: 0.70),
                .single("Light Mono", 5, "#EB8570", position: point(220, 187), opacity: 0.70, texture: 0.12, lightness: 0.70),
                .single("Light Mono", 6, "#DCCE7F", position: point(225, 237), opacity: 0.68, texture: 0.12, lightness: 0.60),
                .single("Light Mono", 7, "#5BECAD", position: point(147, 195), opacity: 0.72, texture: 0.14, lightness: 0.60),
                .single("Light Mono", 8, "#919BB5", position: point(81, 84), opacity: 0.66, texture: 0.10, lightness: 0.50),
            ]
        ),
        SumiWorkspaceThemePresetGroup(
            name: "Light Analogous",
            presets: [
                .trio("Light Analogous", 1, ["#F5EDD6", "#DDF3D8", "#F3D8E1"], position: point(240, 240), opacity: 0.70, texture: 0.10, lightness: 0.90),
                .trio("Light Analogous", 2, ["#F3BEDE", "#F7DEBA", "#DFC3EE"], position: point(233, 157), opacity: 0.70, texture: 0.10, lightness: 0.85),
                .trio("Light Analogous", 3, ["#E5B3E4", "#ECACB2", "#C5B9DF"], position: point(236, 111), opacity: 0.72, texture: 0.11, lightness: 0.80),
                .trio("Light Analogous", 4, ["#EB7A9F", "#EFEF76", "#D285E0"], position: point(234, 173), opacity: 0.76, texture: 0.12, lightness: 0.70),
                .trio("Light Analogous", 5, ["#F2737B", "#AFF273", "#E67DE8"], position: point(220, 187), opacity: 0.76, texture: 0.12, lightness: 0.70),
                .trio("Light Analogous", 6, ["#DDCD55", "#61D45E", "#D75B7C"], position: point(225, 237), opacity: 0.74, texture: 0.12, lightness: 0.60),
                .trio("Light Analogous", 7, ["#4BE7D2", "#54AFDE", "#3EF470"], position: point(147, 195), opacity: 0.78, texture: 0.13, lightness: 0.60),
                .trio("Light Analogous", 8, ["#7A849E", "#8975A4", "#74A2A4"], position: point(81, 84), opacity: 0.72, texture: 0.10, lightness: 0.55),
            ]
        ),
        SumiWorkspaceThemePresetGroup(
            name: "Dark Mono",
            presets: [
                .single("Dark Mono", 1, "#5D566A", position: point(171, 72), opacity: 0.84, texture: 0.18, lightness: 0.10),
                .single("Dark Mono", 2, "#997096", position: point(265, 79), opacity: 0.86, texture: 0.18, lightness: 0.40),
                .single("Dark Mono", 3, "#956066", position: point(301, 176), opacity: 0.86, texture: 0.18, lightness: 0.35),
                .single("Dark Mono", 4, "#9C6645", position: point(237, 210), opacity: 0.88, texture: 0.19, lightness: 0.30),
                .single("Dark Mono", 5, "#517B6C", position: point(91, 228), opacity: 0.86, texture: 0.18, lightness: 0.30),
                .single("Dark Mono", 6, "#576E75", position: point(67, 159), opacity: 0.86, texture: 0.18, lightness: 0.25),
                .single("Dark Mono", 7, "#836D5F", position: point(314, 235), opacity: 0.86, texture: 0.18, lightness: 0.20),
                .single("Dark Mono", 8, "#447464", position: point(118, 215), opacity: 0.86, texture: 0.18, lightness: 0.20),
            ]
        ),
        SumiWorkspaceThemePresetGroup(
            name: "Dark Analogous",
            presets: [
                .trio("Dark Analogous", 1, ["#171122", "#250E23", "#121621"], position: point(171, 72), opacity: 0.90, texture: 0.20, lightness: 0.10),
                .trio("Dark Analogous", 2, ["#804C7C", "#8D3F42", "#615874"], position: point(265, 79), opacity: 0.90, texture: 0.20, lightness: 0.40),
                .trio("Dark Analogous", 3, ["#7A3840", "#7E7934", "#6F446E"], position: point(301, 176), opacity: 0.90, texture: 0.20, lightness: 0.35),
                .trio("Dark Analogous", 4, ["#834116", "#408019", "#7A1F5B"], position: point(237, 210), opacity: 0.92, texture: 0.22, lightness: 0.30),
                .trio("Dark Analogous", 5, ["#2D6C55", "#345565", "#347623"], position: point(91, 228), opacity: 0.90, texture: 0.20, lightness: 0.30),
                .trio("Dark Analogous", 6, ["#2D4A53", "#2E3251", "#265A41"], position: point(67, 159), opacity: 0.90, texture: 0.20, lightness: 0.25),
                .trio("Dark Analogous", 7, ["#402F26", "#374026", "#3B2B34"], position: point(314, 235), opacity: 0.90, texture: 0.20, lightness: 0.20),
                .trio("Dark Analogous", 8, ["#16503D", "#1A3C4C", "#1B570F"], position: point(118, 215), opacity: 0.92, texture: 0.22, lightness: 0.20),
            ]
        ),
        SumiWorkspaceThemePresetGroup(
            name: "Grayscale",
            presets: [
                .single("Grayscale", 1, "#E0E0E0", position: point(340, 180), opacity: 0.58, texture: 0.04, lightness: 0.88, type: .explicitBlackWhite),
                .single("Grayscale", 2, "#E0E0E0", position: point(337.5, 180), opacity: 0.60, texture: 0.04, lightness: 0.88, type: .explicitBlackWhite),
                .single("Grayscale", 3, "#C0C0C0", position: point(315, 180), opacity: 0.62, texture: 0.04, lightness: 0.75, type: .explicitBlackWhite),
                .single("Grayscale", 4, "#A0A0A0", position: point(292.5, 180), opacity: 0.64, texture: 0.04, lightness: 0.63, type: .explicitBlackWhite),
                .single("Grayscale", 5, "#808080", position: point(270, 180), opacity: 0.68, texture: 0.05, lightness: 0.50, type: .explicitBlackWhite),
                .single("Grayscale", 6, "#606060", position: point(247.5, 180), opacity: 0.82, texture: 0.08, lightness: 0.38, type: .explicitBlackWhite),
                .single("Grayscale", 7, "#404040", position: point(225, 180), opacity: 0.86, texture: 0.08, lightness: 0.25, type: .explicitBlackWhite),
                .single("Grayscale", 8, "#202020", position: point(202.5, 180), opacity: 0.90, texture: 0.08, lightness: 0.13, type: .explicitBlackWhite),
                .single("Grayscale", 9, "#000000", position: point(180, 180), opacity: 0.94, texture: 0.08, lightness: 0.0, type: .explicitBlackWhite),
            ]
        ),
    ]

    static var orderedThemes: [WorkspaceTheme] {
        groups.flatMap { $0.presets.map(\.workspaceTheme) }
    }

    static func rotatingTheme(at index: Int) -> WorkspaceTheme {
        let themes = orderedThemes
        guard !themes.isEmpty else { return .default }
        let normalizedIndex = ((index % themes.count) + themes.count) % themes.count
        return themes[normalizedIndex]
    }

    private static func point(_ x: Double, _ y: Double) -> WorkspaceThemePosition {
        WorkspaceThemePosition(x: x / 360.0, y: y / 360.0)
    }
}
