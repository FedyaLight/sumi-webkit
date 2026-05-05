import AppKit
import SwiftUI

struct ZenWorkspaceThemeResolution: Equatable {
    let chromeColorScheme: ColorScheme
    let blackContrast: Double
    let backgroundGradient: SpaceGradient
    let toolbarGradient: SpaceGradient
    let isThemeExplicitScheme: Bool
}

@MainActor
enum ZenWorkspaceThemeResolver {
    private static let toolbarTextAlpha: CGFloat = 0.8
    private static let transparentDarkModeBias: CGFloat = 0.5
    private static let macWhiteOverlayOpacity: CGFloat = 0.35

    static func resolve(
        theme: WorkspaceTheme,
        globalWindowScheme: ColorScheme,
        settings: SumiSettingsService,
        isIncognito: Bool = false
    ) -> ZenWorkspaceThemeResolution {
        let primaryRGB = primaryRGBComponents(for: theme, settings: settings)
        let hasWorkspaceColors = !theme.gradientTheme.normalizedColors.isEmpty
        let usesWorkspaceExplicitScheme = hasWorkspaceColors
            && theme.usesExplicitColorScheme
            && !settings.themeUseSystemColors
            && !isIncognito

        let contrast = contrastDecision(
            primaryRGB: primaryRGB,
            globalWindowScheme: globalWindowScheme,
            settings: settings,
            isIncognito: isIncognito,
            usesWorkspaceExplicitScheme: usesWorkspaceExplicitScheme
        )

        return ZenWorkspaceThemeResolution(
            chromeColorScheme: contrast.scheme,
            blackContrast: contrast.blackContrast,
            backgroundGradient: resolvedGradient(
                theme.gradient,
                forToolbar: false,
                colorSource: theme,
                globalWindowScheme: globalWindowScheme,
                usesWorkspaceExplicitScheme: usesWorkspaceExplicitScheme
            ),
            toolbarGradient: resolvedGradient(
                theme.gradient,
                forToolbar: true,
                colorSource: theme,
                globalWindowScheme: globalWindowScheme,
                usesWorkspaceExplicitScheme: usesWorkspaceExplicitScheme
            ),
            isThemeExplicitScheme: usesWorkspaceExplicitScheme
        )
    }

    static func primaryColor(
        theme: WorkspaceTheme,
        settings: SumiSettingsService
    ) -> Color {
        color(from: primaryRGBComponents(for: theme, settings: settings))
    }

    private static func contrastDecision(
        primaryRGB: [CGFloat],
        globalWindowScheme: ColorScheme,
        settings: SumiSettingsService,
        isIncognito: Bool,
        usesWorkspaceExplicitScheme: Bool
    ) -> (scheme: ColorScheme, blackContrast: Double) {
        if isIncognito {
            return (.dark, 1)
        }

        if settings.themeUseSystemColors || !usesWorkspaceExplicitScheme {
            return (
                globalWindowScheme,
                globalWindowScheme == .light ? 21 : 1
            )
        }

        let whiteText = toolbarTextCandidate(for: .dark)
        var blackText = toolbarTextCandidate(for: .light)
        blackText.alpha = max(0, blackText.alpha - transparentDarkModeBias)

        let whiteComposite = composite(
            foreground: whiteText.rgb,
            alpha: whiteText.alpha,
            over: primaryRGB
        )
        let blackComposite = composite(
            foreground: blackText.rgb,
            alpha: blackText.alpha,
            over: primaryRGB
        )

        let whiteContrast = contrastRatio(between: primaryRGB, and: whiteComposite)
        let blackContrast = contrastRatio(between: primaryRGB, and: blackComposite)

        return (
            whiteContrast > blackContrast ? .dark : .light,
            blackContrast
        )
    }

    private static func resolvedGradient(
        _ gradient: SpaceGradient,
        forToolbar: Bool,
        colorSource theme: WorkspaceTheme,
        globalWindowScheme: ColorScheme,
        usesWorkspaceExplicitScheme: Bool
    ) -> SpaceGradient {
        guard usesWorkspaceExplicitScheme else {
            return defaultThemeGradient(
                for: globalWindowScheme,
                forToolbar: forToolbar
            )
        }

        let colorsByID = Dictionary(
            uniqueKeysWithValues: theme.gradientTheme.normalizedColors.map { ($0.id, $0) }
        )
        let nodes = gradient.sortedNodes.map { node -> GradientNode in
            let color = colorsByID[node.id]
            let rgb = rgbComponents(of: Color(hex: color?.hex ?? node.colorHex))
            let resolvedRGB = resolvedSingleRGBColor(
                rgb,
                opacity: gradient.opacity,
                isCustom: color?.isCustom ?? false,
                forToolbar: forToolbar,
                globalWindowScheme: globalWindowScheme
            )
            return GradientNode(
                id: node.id,
                colorHex: hexString(from: resolvedRGB),
                location: node.location,
                xPosition: node.xPosition,
                yPosition: node.yPosition
            )
        }

        return SpaceGradient(
            angle: gradient.angle,
            nodes: nodes,
            grain: gradient.grain,
            opacity: forToolbar ? 1 : gradient.opacity
        )
    }

    private static func defaultThemeGradient(
        for globalWindowScheme: ColorScheme,
        forToolbar: Bool
    ) -> SpaceGradient {
        let color: Color = {
            switch globalWindowScheme {
            case .light:
                return Color(.sRGB, red: 235 / 255, green: 235 / 255, blue: 235 / 255, opacity: 1)
            case .dark:
                return Color(hex: "1B1B1B")
            @unknown default:
                return Color(.sRGB, red: 235 / 255, green: 235 / 255, blue: 235 / 255, opacity: 1)
            }
        }()
        let rgb = rgbComponents(of: color)
        let resolvedRGB = forToolbar
            ? resolvedToolbarRGB(rgb, globalWindowScheme: globalWindowScheme)
            : rgb

        return SpaceGradient(
            angle: 225,
            nodes: [
                GradientNode(
                    colorHex: hexString(from: resolvedRGB),
                    location: 0,
                    xPosition: 0.5,
                    yPosition: 0.5
                )
            ],
            grain: 0,
            opacity: 1
        )
    }

    private static func resolvedSingleRGBColor(
        _ rgb: [CGFloat],
        opacity: Double,
        isCustom: Bool,
        forToolbar: Bool,
        globalWindowScheme: ColorScheme
    ) -> [CGFloat] {
        if isCustom {
            return rgb
        }

        var color = rgb
        var resolvedOpacity = max(0, min(1, CGFloat(opacity)))

        if forToolbar {
            color = resolvedToolbarRGB(
                color,
                globalWindowScheme: globalWindowScheme
            )
            resolvedOpacity = 1
        }

        return blendWithMacWhiteOverlay(color, opacity: resolvedOpacity)
    }

    private static func resolvedToolbarRGB(
        _ rgb: [CGFloat],
        globalWindowScheme: ColorScheme
    ) -> [CGFloat] {
        blend(
            rgb,
            with: toolbarModifiedBaseRGB(for: globalWindowScheme),
            preservingFirstBy: 0.90
        )
    }

    private static func blendWithMacWhiteOverlay(
        _ rgb: [CGFloat],
        opacity: CGFloat
    ) -> [CGFloat] {
        let minOpacity = CGFloat(WorkspaceGradientTheme.minimumOpacity)
        let blendedAlpha = min(
            1,
            opacity + minOpacity + macWhiteOverlayOpacity * (1 - (opacity + minOpacity))
        )
        return blend(rgb, with: [1, 1, 1], preservingFirstBy: blendedAlpha)
    }

    private static func primaryRGBComponents(
        for theme: WorkspaceTheme,
        settings: SumiSettingsService
    ) -> [CGFloat] {
        if settings.themeUseSystemColors {
            return rgbComponents(of: Color(nsColor: .controlAccentColor))
        }

        guard let primary = theme.gradientTheme.normalizedColors.first(where: { $0.isPrimary })
            ?? theme.gradientTheme.normalizedColors.first
        else {
            return rgbComponents(of: Color(nsColor: .controlAccentColor))
        }

        return rgbComponents(of: Color(hex: primary.hex))
    }

    private static func toolbarTextCandidate(
        for chromeScheme: ColorScheme
    ) -> (rgb: [CGFloat], alpha: CGFloat) {
        switch chromeScheme {
        case .light:
            return ([0, 0, 0], toolbarTextAlpha)
        case .dark:
            return ([1, 1, 1], toolbarTextAlpha)
        @unknown default:
            return ([0, 0, 0], toolbarTextAlpha)
        }
    }

    private static func toolbarModifiedBaseRGB(for globalWindowScheme: ColorScheme) -> [CGFloat] {
        switch globalWindowScheme {
        case .light:
            return [
                240 / 255,
                240 / 255,
                244 / 255,
            ]
        case .dark:
            return [
                23 / 255,
                23 / 255,
                26 / 255,
            ]
        @unknown default:
            return [
                240 / 255,
                240 / 255,
                244 / 255,
            ]
        }
    }

    private static func rgbComponents(of color: Color) -> [CGFloat] {
        let components = color.sRGBComponents
        return [components.red, components.green, components.blue]
    }

    private static func color(from rgb: [CGFloat]) -> Color {
        Color(
            .sRGB,
            red: max(0, min(1, rgb[0])),
            green: max(0, min(1, rgb[1])),
            blue: max(0, min(1, rgb[2])),
            opacity: 1
        )
    }

    private static func hexString(from rgb: [CGFloat]) -> String {
        let r = Int(round(max(0, min(1, rgb[0])) * 255))
        let g = Int(round(max(0, min(1, rgb[1])) * 255))
        let b = Int(round(max(0, min(1, rgb[2])) * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func blend(
        _ first: [CGFloat],
        with second: [CGFloat],
        preservingFirstBy amount: CGFloat
    ) -> [CGFloat] {
        let p = max(0, min(1, amount))
        return [
            first[0] * p + second[0] * (1 - p),
            first[1] * p + second[1] * (1 - p),
            first[2] * p + second[2] * (1 - p),
        ]
    }

    private static func composite(
        foreground: [CGFloat],
        alpha: CGFloat,
        over background: [CGFloat]
    ) -> [CGFloat] {
        [
            foreground[0] * alpha + background[0] * (1 - alpha),
            foreground[1] * alpha + background[1] * (1 - alpha),
            foreground[2] * alpha + background[2] * (1 - alpha),
        ]
    }

    private static func contrastRatio(
        between lhs: [CGFloat],
        and rhs: [CGFloat]
    ) -> Double {
        let lum1 = luminance(lhs)
        let lum2 = luminance(rhs)
        let brightest = max(lum1, lum2)
        let darkest = min(lum1, lum2)
        return (brightest + 0.05) / (darkest + 0.05)
    }

    private static func luminance(_ rgb: [CGFloat]) -> Double {
        let mapped = rgb.map { value -> Double in
            let v = Double(value)
            return v <= 0.03928
                ? v / 12.92
                : pow((v + 0.055) / 1.055, 2.4)
        }
        return mapped[0] * 0.2126 + mapped[1] * 0.7152 + mapped[2] * 0.0722
    }
}
