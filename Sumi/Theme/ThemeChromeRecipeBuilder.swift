import AppKit
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
            ? Color.white.opacity(0.96)
            : Color.black.opacity(0.88)
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
            return Color.black.opacity(0.84)
        case .dark:
            return Color.white.opacity(0.92)
        @unknown default:
            return Color.primary
        }
    }

    static func secondaryText(for chromeScheme: ColorScheme) -> Color {
        switch chromeScheme {
        case .light:
            return Color.black.opacity(0.56)
        case .dark:
            return Color.white.opacity(0.68)
        @unknown default:
            return Color.secondary
        }
    }

    static func tertiaryText(for chromeScheme: ColorScheme) -> Color {
        switch chromeScheme {
        case .light:
            return Color.black.opacity(0.38)
        case .dark:
            return Color.white.opacity(0.46)
        @unknown default:
            return Color.secondary.opacity(0.6)
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

@MainActor
private struct ThemeChromePalette {
    let background: Color
    let fieldBackground: Color
    let fieldBackgroundHover: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let chromeControlHoverBackground: Color
    let chromeControlPressedBackground: Color
    let sidebarRowActive: Color
    let sidebarRowHover: Color
    let sidebarSelectionShadow: Color
    let pinnedActiveBackground: Color
    let pinnedHoverBackground: Color
    let pinnedIdleBackground: Color
    let separator: Color
    let toastBackground: Color
    let toastBorder: Color
    let toastPrimaryText: Color
    let toastSecondaryText: Color
    let toastIconBackground: Color
    let statusPanelBackground: Color
    let statusPanelBorder: Color
    let statusPanelText: Color
    let buttonPrimaryBackground: Color
    let buttonPrimaryText: Color
    let buttonSecondaryBackground: Color
    let windowBackground: Color
    let floatingBarBackground: Color
    let floatingBarChipBackground: Color
    let floatingBarRowSelected: Color
    let floatingBarRowHover: Color

    static func make(
        scheme: ColorScheme,
        accent: Color,
        settings: SumiSettingsService
    ) -> ThemeChromePalette {
        let background = ThemeChromeRecipeBuilder.neutralChromeBackground(
            for: scheme,
            settings: settings
        )
        let elevatedStrong = ThemeChromeRecipeBuilder.elevatedNeutral(
            for: scheme,
            background: background,
            emphasis: 0.6,
            settings: settings
        )
        let elevatedSubtle = ThemeChromeRecipeBuilder.elevatedNeutral(
            for: scheme,
            background: background,
            emphasis: 0.28,
            settings: settings
        )
        let primaryText = ThemeContrastResolver.primaryText(for: scheme)
        let secondaryText = ThemeContrastResolver.secondaryText(for: scheme)
        let tertiaryText = ThemeContrastResolver.tertiaryText(for: scheme)
        let chromeControlHoverBackground = primaryText.opacity(scheme == .dark ? 0.20 : 0.10)
        let chromeControlPressedBackground = primaryText.opacity(scheme == .dark ? 0.24 : 0.16)
        let buttonPrimaryText = ThemeContrastResolver.preferredForeground(on: accent)
        let fieldBackground = ThemeChromeRecipeBuilder.zenToolbarElementBackground(scheme: scheme)
        let fieldBackgroundHover = ThemeChromeRecipeBuilder.zenToolbarElementHoverBackground(
            elementBackground: fieldBackground,
            scheme: scheme
        )
        let floatingBarBackground = ThemeChromeRecipeBuilder.floatingBarSolidBackground(scheme: scheme)
        let floatingBarChipBackground = ThemeChromeRecipeBuilder.floatingBarChipBackground(scheme: scheme)
        let floatingBarRowSelected = ThemeChromeRecipeBuilder.floatingBarRowSelected(scheme: scheme)
        let floatingBarRowHover = ThemeChromeRecipeBuilder.floatingBarRowHover(scheme: scheme)
        let sidebarRowActive: Color = {
            switch scheme {
            case .light:
                return Color.white.opacity(0.8)
            case .dark:
                return Color.white.opacity(0.18)
            @unknown default:
                return Color.white.opacity(0.2)
            }
        }()
        let sidebarRowHover: Color = {
            switch scheme {
            case .light:
                return Color.black.opacity(0.1)
            case .dark:
                return Color.white.opacity(0.1)
            @unknown default:
                return Color.primary.opacity(0.1)
            }
        }()
        let sidebarSelectionShadow: Color = {
            switch scheme {
            case .light:
                return Color.black.opacity(0.09)
            case .dark:
                return Color.black.opacity(0.05)
            @unknown default:
                return Color.black.opacity(0.08)
            }
        }()

        let separator: Color = {
            switch scheme {
            case .light:
                return Color.black.opacity(0.12)
            case .dark:
                return Color.white.opacity(0.26)
            @unknown default:
                return Color.primary.opacity(0.14)
            }
        }()

        return ThemeChromePalette(
            background: background,
            fieldBackground: fieldBackground,
            fieldBackgroundHover: fieldBackgroundHover,
            primaryText: primaryText,
            secondaryText: secondaryText,
            tertiaryText: tertiaryText,
            chromeControlHoverBackground: chromeControlHoverBackground,
            chromeControlPressedBackground: chromeControlPressedBackground,
            sidebarRowActive: sidebarRowActive,
            sidebarRowHover: sidebarRowHover,
            sidebarSelectionShadow: sidebarSelectionShadow,
            // Match selected tab rows (`SpaceTab`, `SplitTabRow`): white lift when the live tab is this essential.
            pinnedActiveBackground: sidebarRowActive,
            pinnedHoverBackground: fieldBackgroundHover,
            pinnedIdleBackground: fieldBackground,
            separator: separator,
            toastBackground: elevatedStrong.opacity(0.98),
            toastBorder: separator.opacity(scheme == .dark ? 0.7 : 1.0),
            toastPrimaryText: primaryText,
            toastSecondaryText: secondaryText,
            toastIconBackground: elevatedSubtle.opacity(scheme == .dark ? 0.72 : 0.8),
            statusPanelBackground: elevatedStrong.opacity(0.98),
            statusPanelBorder: separator.opacity(scheme == .dark ? 0.72 : 0.9),
            statusPanelText: primaryText,
            buttonPrimaryBackground: accent,
            buttonPrimaryText: buttonPrimaryText,
            buttonSecondaryBackground: elevatedSubtle.opacity(scheme == .dark ? 0.9 : 1.0),
            windowBackground: {
                switch scheme {
                case .light:
                    return background.mixed(with: .white, amount: 0.82)
                case .dark:
                    return background.mixed(with: .black, amount: 0.38)
                @unknown default:
                    return background
                }
            }(),
            floatingBarBackground: floatingBarBackground,
            floatingBarChipBackground: floatingBarChipBackground,
            floatingBarRowSelected: floatingBarRowSelected,
            floatingBarRowHover: floatingBarRowHover
        )
    }

    func interpolated(to other: ThemeChromePalette, progress: Double) -> ThemeChromePalette {
        let clamped = min(max(progress, 0), 1)

        func mix(_ lhs: Color, _ rhs: Color) -> Color {
            lhs.mixed(with: rhs, amount: clamped)
        }

        return ThemeChromePalette(
            background: mix(background, other.background),
            fieldBackground: mix(fieldBackground, other.fieldBackground),
            fieldBackgroundHover: mix(fieldBackgroundHover, other.fieldBackgroundHover),
            primaryText: mix(primaryText, other.primaryText),
            secondaryText: mix(secondaryText, other.secondaryText),
            tertiaryText: mix(tertiaryText, other.tertiaryText),
            chromeControlHoverBackground: mix(chromeControlHoverBackground, other.chromeControlHoverBackground),
            chromeControlPressedBackground: mix(chromeControlPressedBackground, other.chromeControlPressedBackground),
            sidebarRowActive: mix(sidebarRowActive, other.sidebarRowActive),
            sidebarRowHover: mix(sidebarRowHover, other.sidebarRowHover),
            sidebarSelectionShadow: mix(sidebarSelectionShadow, other.sidebarSelectionShadow),
            pinnedActiveBackground: mix(pinnedActiveBackground, other.pinnedActiveBackground),
            pinnedHoverBackground: mix(pinnedHoverBackground, other.pinnedHoverBackground),
            pinnedIdleBackground: mix(pinnedIdleBackground, other.pinnedIdleBackground),
            separator: mix(separator, other.separator),
            toastBackground: mix(toastBackground, other.toastBackground),
            toastBorder: mix(toastBorder, other.toastBorder),
            toastPrimaryText: mix(toastPrimaryText, other.toastPrimaryText),
            toastSecondaryText: mix(toastSecondaryText, other.toastSecondaryText),
            toastIconBackground: mix(toastIconBackground, other.toastIconBackground),
            statusPanelBackground: mix(statusPanelBackground, other.statusPanelBackground),
            statusPanelBorder: mix(statusPanelBorder, other.statusPanelBorder),
            statusPanelText: mix(statusPanelText, other.statusPanelText),
            buttonPrimaryBackground: mix(buttonPrimaryBackground, other.buttonPrimaryBackground),
            buttonPrimaryText: mix(buttonPrimaryText, other.buttonPrimaryText),
            buttonSecondaryBackground: mix(buttonSecondaryBackground, other.buttonSecondaryBackground),
            windowBackground: mix(windowBackground, other.windowBackground),
            floatingBarBackground: mix(floatingBarBackground, other.floatingBarBackground),
            floatingBarChipBackground: mix(floatingBarChipBackground, other.floatingBarChipBackground),
            floatingBarRowSelected: mix(floatingBarRowSelected, other.floatingBarRowSelected),
            floatingBarRowHover: mix(floatingBarRowHover, other.floatingBarRowHover)
        )
    }

    func resolve(accent: Color) -> ChromeThemeTokens {
        ChromeThemeTokens(
            accent: accent,
            fieldBackground: fieldBackground,
            fieldBackgroundHover: fieldBackgroundHover,
            primaryText: primaryText,
            secondaryText: secondaryText,
            tertiaryText: tertiaryText,
            chromeControlHoverBackground: chromeControlHoverBackground,
            chromeControlPressedBackground: chromeControlPressedBackground,
            sidebarRowActive: sidebarRowActive,
            sidebarRowHover: sidebarRowHover,
            sidebarSelectionShadow: sidebarSelectionShadow,
            pinnedActiveBackground: pinnedActiveBackground,
            pinnedHoverBackground: pinnedHoverBackground,
            pinnedIdleBackground: pinnedIdleBackground,
            separator: separator,
            toastBackground: toastBackground,
            toastBorder: toastBorder,
            toastPrimaryText: toastPrimaryText,
            toastSecondaryText: toastSecondaryText,
            toastIconBackground: toastIconBackground,
            statusPanelBackground: statusPanelBackground,
            statusPanelBorder: statusPanelBorder,
            statusPanelText: statusPanelText,
            buttonPrimaryBackground: buttonPrimaryBackground,
            buttonPrimaryText: buttonPrimaryText,
            buttonSecondaryBackground: buttonSecondaryBackground,
            windowBackground: windowBackground,
            floatingBarBackground: floatingBarBackground,
            floatingBarChipBackground: floatingBarChipBackground,
            floatingBarRowSelected: floatingBarRowSelected,
            floatingBarRowHover: floatingBarRowHover
        )
    }
}

@MainActor
enum ThemeChromeRecipeBuilder {
    static func makeTokens(
        context: ResolvedThemeContext,
        settings: SumiSettingsService
    ) -> ChromeThemeTokens {
        let sourceAccent = ZenWorkspaceThemeResolver.primaryColor(
            theme: context.sourceWorkspaceTheme,
            settings: settings
        )
        let targetAccent = ZenWorkspaceThemeResolver.primaryColor(
            theme: context.targetWorkspaceTheme,
            settings: settings
        )

        let sourcePalette = ThemeChromePalette.make(
            scheme: context.sourceChromeColorScheme,
            accent: sourceAccent,
            settings: settings
        )
        let targetPalette = ThemeChromePalette.make(
            scheme: context.targetChromeColorScheme,
            accent: targetAccent,
            settings: settings
        )

        let needsInterpolation =
            context.sourceChromeColorScheme != context.targetChromeColorScheme
            || context.sourceWorkspaceTheme != context.targetWorkspaceTheme
            || context.transitionProgress < 1.0

        let accent = needsInterpolation
            ? sourceAccent.mixed(
                with: targetAccent,
                amount: CGFloat(context.transitionProgress)
            )
            : targetAccent
        let palette = needsInterpolation
            ? sourcePalette.interpolated(
                to: targetPalette,
                progress: context.transitionProgress
            )
            : targetPalette

        return palette.resolve(accent: accent)
    }

    /// Sidebar / toolbox chrome base without user-accent tint (Zen branding neutrals).
    static func neutralChromeBackground(
        for scheme: ColorScheme,
        settings: SumiSettingsService
    ) -> Color {
        switch scheme {
        case .light:
            return Color.white
        case .dark:
            switch settings.darkThemeStyle {
            case .default:
                return Color(hex: "12151A")
            case .night:
                return Color(hex: "0C1015")
            case .colorful:
                return Color(hex: "151A24")
            }
        @unknown default:
            return Color(nsColor: .windowBackgroundColor)
        }
    }

    /// Lift surfaces using neutral mixes (toolbar, panels), not accent washes.
    static func elevatedNeutral(
        for scheme: ColorScheme,
        background: Color,
        emphasis: CGFloat,
        settings: SumiSettingsService
    ) -> Color {
        switch scheme {
        case .light:
            return background.mixed(with: .white, amount: 0.05 + emphasis * 0.10)
        case .dark:
            let lift: CGFloat
            switch settings.darkThemeStyle {
            case .default:
                lift = 0.06 + emphasis * 0.12
            case .night:
                lift = 0.04 + emphasis * 0.09
            case .colorful:
                lift = 0.08 + emphasis * 0.14
            }
            return background.mixed(with: Color.white.opacity(0.28), amount: lift)
        @unknown default:
            return background
        }
    }

    /// Zen `--zen-toolbar-element-bg`: translucent ink only, composited over the window gradient (no opaque cream base).
    static func zenToolbarElementBackground(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color.black.opacity(0.08)
        case .dark:
            return Color.white.opacity(0.12)
        @unknown default:
            return Color.black.opacity(0.08)
        }
    }

    /// Zen `--zen-toolbar-element-bg-hover` on top of the resting veil.
    static func zenToolbarElementHoverBackground(
        elementBackground: Color,
        scheme: ColorScheme
    ) -> Color {
        let overlay: Color = {
            switch scheme {
            case .light:
                return Color.black.opacity(0.08)
            case .dark:
                return Color.white.opacity(0.10)
            @unknown default:
                return Color.black.opacity(0.08)
            }
        }()
        return elementBackground.overlaying(overlay)
    }

    static func floatingBarSolidBackground(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color.white
        case .dark:
            return Color(hex: "1C1C1E")
        @unknown default:
            return Color.white
        }
    }

    static func floatingBarChipBackground(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color.black.opacity(0.06)
        case .dark:
            return Color.white.opacity(0.10)
        @unknown default:
            return Color.black.opacity(0.06)
        }
    }

    static func floatingBarRowSelected(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color.black.opacity(0.08)
        case .dark:
            return Color.white.opacity(0.14)
        @unknown default:
            return Color.black.opacity(0.08)
        }
    }

    static func floatingBarRowHover(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color.black.opacity(0.05)
        case .dark:
            return Color.white.opacity(0.08)
        @unknown default:
            return Color.black.opacity(0.05)
        }
    }

    // MARK: - URL bar / hub veil gradients

    /// Vertical gradient stops for hub header tiles, extension hub tiles, and similar Zen veil controls. Centralizes top/bottom opacity on `fieldBackground*` veils.
    static func urlBarHubVeilGradientColors(
        tokens: ChromeThemeTokens,
        isActive: Bool,
        isHovered: Bool
    ) -> [Color] {
        let topOpacity: CGFloat = {
            if isHovered { return 1.0 }
            return isActive ? 0.95 : 0.92
        }()
        let bottomOpacity: CGFloat = isActive ? 0.98 : 0.96
        return [
            tokens.fieldBackgroundHover.opacity(topOpacity),
            tokens.fieldBackground.opacity(bottomOpacity),
        ]
    }

    /// Background for small URL toolbar icon buttons (hover / pressed on veil).
    static func urlBarToolbarIconButtonBackground(
        tokens: ChromeThemeTokens,
        isHovering: Bool,
        isPressed: Bool,
        isEnabled: Bool
    ) -> Color {
        guard isEnabled, isHovering || isPressed else { return .clear }
        return isPressed ? tokens.fieldBackgroundHover.opacity(0.92) : tokens.fieldBackgroundHover
    }

    /// Segmented / pill control on the URL field veil (pressed vs idle).
    static func urlBarPillFieldBackground(
        tokens: ChromeThemeTokens,
        isPressed: Bool,
        isHovering: Bool,
        isEnabled: Bool
    ) -> Color {
        guard isEnabled else { return tokens.fieldBackground }
        if isPressed {
            return tokens.fieldBackgroundHover.opacity(0.95)
        }
        if isHovering {
            return tokens.fieldBackgroundHover
        }
        return tokens.fieldBackground
    }
}
