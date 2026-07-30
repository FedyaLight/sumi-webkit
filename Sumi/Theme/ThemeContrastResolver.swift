import AppKit
import SumiDomain
import SwiftUI

struct ThemeContrastDecision: Equatable {
    let chromeColorScheme: ColorScheme
    let blackContrast: Double
}
@MainActor
enum ThemeContrastResolver {
    enum ContrastDirectionPreference {
        case automatic
        case preferLight
        case preferDark
        case forceLight
        case forceDark
    }

    static func resolvedChromeColorScheme(
        theme: WorkspaceTheme,
        globalWindowScheme: ColorScheme,
        settings: SumiSettingsService,
        isIncognito: Bool = false
    ) -> ColorScheme {
        decision(
            theme: theme,
            globalWindowScheme: globalWindowScheme,
            settings: settings,
            isIncognito: isIncognito
        ).chromeColorScheme
    }

    static func decision(
        theme: WorkspaceTheme,
        globalWindowScheme: ColorScheme,
        settings: SumiSettingsService,
        isIncognito: Bool = false
    ) -> ThemeContrastDecision {
        if isIncognito {
            return ThemeContrastDecision(
                chromeColorScheme: .dark,
                blackContrast: 1
            )
        }

        if settings.themeUseSystemColors {
            return ThemeContrastDecision(
                chromeColorScheme: globalWindowScheme,
                blackContrast: globalWindowScheme == .light ? 21 : 1
            )
        }

        let zenResolution = ZenWorkspaceThemeResolver.resolve(
            theme: theme,
            globalWindowScheme: globalWindowScheme,
            settings: settings,
            isIncognito: isIncognito
        )

        return ThemeContrastDecision(
            chromeColorScheme: zenResolution.chromeColorScheme,
            blackContrast: zenResolution.blackContrast
        )
    }

    static func preferredForeground(on background: Color) -> Color {
        let rgb = rgbComponents(of: background)
        let white = contrastRatio(
            between: rgb,
            and: [1, 1, 1]
        )
        let black = contrastRatio(
            between: rgb,
            and: [0, 0, 0]
        )
        return white > black
            ? ThemeChromeRecipeColors.Foreground.preferredLight
            : ThemeChromeRecipeColors.Foreground.preferredDark
    }

    static func contrastingShade(
        of color: Color,
        targetRatio: CGFloat = 4.5,
        directionPreference: ContrastDirectionPreference = .automatic,
        minimumBlend: CGFloat = 0
    ) -> Color? {
        let candidateOrder = candidateBaseColors(
            for: color,
            directionPreference: directionPreference
        )

        for candidate in candidateOrder {
            if let shade = blendedShade(
                from: color,
                toward: candidate,
                targetRatio: targetRatio,
                minimumBlend: minimumBlend
            ) {
                return shade
            }
        }

        return nil
    }

    static func primaryText(for chromeScheme: ColorScheme) -> Color {
        switch chromeScheme {
        case .light:
            return ThemeChromeRecipeColors.Foreground.primaryLight
        case .dark:
            return ThemeChromeRecipeColors.Foreground.primaryDark
        @unknown default:
            return ThemeChromeRecipeColors.Foreground.primaryFallback
        }
    }

    static func secondaryText(for chromeScheme: ColorScheme) -> Color {
        switch chromeScheme {
        case .light:
            return ThemeChromeRecipeColors.Foreground.secondaryLight
        case .dark:
            return ThemeChromeRecipeColors.Foreground.secondaryDark
        @unknown default:
            return ThemeChromeRecipeColors.Foreground.secondaryFallback
        }
    }

    static func tertiaryText(for chromeScheme: ColorScheme) -> Color {
        switch chromeScheme {
        case .light:
            return ThemeChromeRecipeColors.Foreground.tertiaryLight
        case .dark:
            return ThemeChromeRecipeColors.Foreground.tertiaryDark
        @unknown default:
            return ThemeChromeRecipeColors.Foreground.tertiaryFallback
        }
    }

    private static func rgbComponents(of color: Color) -> [CGFloat] {
        let components = color.sRGBComponents
        return [components.red, components.green, components.blue]
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

    private static func candidateBaseColors(
        for color: Color,
        directionPreference: ContrastDirectionPreference
    ) -> [Color] {
        switch directionPreference {
        case .forceLight:
            return [.white, .black]
        case .forceDark:
            return [.black, .white]
        case .preferLight:
            return [.white, .black]
        case .preferDark:
            return [.black, .white]
        case .automatic:
            let preferred = preferredForeground(on: color)
            let prefersLight = preferred.contrastRatio(with: .white) < preferred.contrastRatio(with: .black)
            return prefersLight ? [.white, .black] : [.black, .white]
        }
    }

    private static func blendedShade(
        from color: Color,
        toward candidate: Color,
        targetRatio: CGFloat,
        minimumBlend: CGFloat
    ) -> Color? {
        let clampedMinimumBlend = max(0, min(1, minimumBlend))
        let fullyBlended = color.mixed(with: candidate, amount: 1)
        guard fullyBlended.contrastRatio(with: color) >= Double(targetRatio) else {
            return nil
        }

        var lowerBound = clampedMinimumBlend
        var upperBound: CGFloat = 1
        var bestShade = color.mixed(with: candidate, amount: upperBound)

        for _ in 0..<16 {
            let midpoint = (lowerBound + upperBound) / 2
            let shade = color.mixed(with: candidate, amount: midpoint)
            if shade.contrastRatio(with: color) >= Double(targetRatio) {
                bestShade = shade
                upperBound = midpoint
            } else {
                lowerBound = midpoint
            }
        }

        return bestShade
    }
}
