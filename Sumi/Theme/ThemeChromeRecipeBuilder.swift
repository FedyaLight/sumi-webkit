import AppKit
import SumiDomain
import SwiftUI

@MainActor
struct ChromeThemeRecipe {
    let sourceAccent: Color
    let targetAccent: Color
    let sourcePalette: ThemeChromePalette
    let targetPalette: ThemeChromePalette

    func tokens(progress: Double, usesTransition: Bool) -> ChromeThemeTokens {
        guard usesTransition else {
            return targetPalette.resolve(accent: targetAccent)
        }

        let clampedProgress = min(max(progress, 0), 1)
        return sourcePalette
            .interpolated(to: targetPalette, progress: clampedProgress)
            .resolve(
                accent: sourceAccent.mixed(
                    with: targetAccent,
                    amount: CGFloat(clampedProgress)
                )
            )
    }
}

@MainActor
enum ThemeChromeRecipeBuilder {
    #if DEBUG
        static var recipeBuildCountForTests = 0
    #endif

    static func makeRecipe(
        context: ResolvedThemeContext,
        settings: SumiSettingsService
    ) -> ChromeThemeRecipe {
        #if DEBUG
            recipeBuildCountForTests += 1
        #endif
        return PerformanceTrace.withInterval("Theme.chromeRecipeBuild") {
            let sourceAccent = ZenWorkspaceThemeResolver.primaryColor(
                theme: context.sourceWorkspaceTheme,
                settings: settings
            )
            let targetAccent = ZenWorkspaceThemeResolver.primaryColor(
                theme: context.targetWorkspaceTheme,
                settings: settings
            )

            return ChromeThemeRecipe(
                sourceAccent: sourceAccent,
                targetAccent: targetAccent,
                sourcePalette: ThemeChromePalette.make(
                    scheme: context.sourceChromeColorScheme,
                    accent: sourceAccent,
                    settings: settings
                ),
                targetPalette: ThemeChromePalette.make(
                    scheme: context.targetChromeColorScheme,
                    accent: targetAccent,
                    settings: settings
                )
            )
        }
    }

    /// Sidebar / toolbox chrome base without user-accent tint (Zen branding neutrals).
    static func neutralChromeBackground(
        for scheme: ColorScheme,
        settings: SumiSettingsService
    ) -> Color {
        switch scheme {
        case .light:
            return ThemeChromeRecipeColors.Neutral.lightBackground
        case .dark:
            switch settings.darkThemeStyle {
            case .default:
                return ThemeChromeRecipeColors.Neutral.darkDefaultBackground
            case .night:
                return ThemeChromeRecipeColors.Neutral.darkNightBackground
            case .colorful:
                return ThemeChromeRecipeColors.Neutral.darkColorfulBackground
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
            return background.mixed(with: ThemeChromeRecipeColors.Neutral.elevatedDarkOverlay, amount: lift)
        @unknown default:
            return background
        }
    }

    /// Zen `--zen-toolbar-element-bg`: translucent ink only, composited over the window gradient (no opaque cream base).
    static func zenToolbarElementBackground(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return ThemeChromeRecipeColors.Neutral.toolbarLight
        case .dark:
            return ThemeChromeRecipeColors.Neutral.toolbarDark
        @unknown default:
            return ThemeChromeRecipeColors.Neutral.toolbarFallback
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
                return ThemeChromeRecipeColors.Neutral.toolbarHoverLight
            case .dark:
                return ThemeChromeRecipeColors.Neutral.toolbarHoverDark
            @unknown default:
                return ThemeChromeRecipeColors.Neutral.toolbarHoverFallback
            }
        }()
        return elementBackground.overlaying(overlay)
    }

    static func floatingSurfaceBackground(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return ThemeChromeRecipeColors.FloatingSurface.backgroundLight
        case .dark:
            return ThemeChromeRecipeColors.FloatingSurface.backgroundDark
        @unknown default:
            return ThemeChromeRecipeColors.FloatingSurface.backgroundFallback
        }
    }

    static func floatingSurfaceBorder(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return ThemeChromeRecipeColors.FloatingSurface.borderLight
        case .dark:
            return ThemeChromeRecipeColors.FloatingSurface.borderDark
        @unknown default:
            return ThemeChromeRecipeColors.FloatingSurface.borderFallback
        }
    }

    static func floatingSurfaceSecondaryBackground(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return ThemeChromeRecipeColors.FloatingSurface.secondaryLight
        case .dark:
            return ThemeChromeRecipeColors.FloatingSurface.secondaryDark
        @unknown default:
            return ThemeChromeRecipeColors.FloatingSurface.secondaryFallback
        }
    }

    static func floatingSurfaceSelection(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return ThemeChromeRecipeColors.FloatingSurface.selectionLight
        case .dark:
            return ThemeChromeRecipeColors.FloatingSurface.selectionDark
        @unknown default:
            return ThemeChromeRecipeColors.FloatingSurface.selectionFallback
        }
    }

    static func floatingSurfaceHover(scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return ThemeChromeRecipeColors.FloatingSurface.hoverLight
        case .dark:
            return ThemeChromeRecipeColors.FloatingSurface.hoverDark
        @unknown default:
            return ThemeChromeRecipeColors.FloatingSurface.hoverFallback
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
