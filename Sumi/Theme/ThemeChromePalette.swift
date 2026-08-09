import AppKit
import SumiDomain
import SwiftUI

@MainActor
struct ThemeChromePalette {
    let background: Color
    let fieldBackground: Color
    let fieldBackgroundHover: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let chromeControlHoverBackground: Color
    let chromeControlPressedBackground: Color
    let chromeNavigationControlDisabledAlpha: CGFloat
    let popoverActionDisabledAlpha: CGFloat
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
    let floatingSurfaceBackground: Color
    let floatingSurfaceBorder: Color
    let floatingSurfaceSecondaryBackground: Color
    let floatingSurfaceSelection: Color
    let floatingSurfaceHover: Color

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
        let chromeNavigationControlDisabledAlpha: CGFloat =
            ChromeLayoutTokens.chromeNavigationControlDisabledAlpha
        let popoverActionDisabledAlpha: CGFloat =
            ChromeLayoutTokens.popoverActionDisabledAlpha
        let buttonPrimaryText = ThemeContrastResolver.preferredForeground(on: accent)
        let fieldBackground = ThemeChromeRecipeBuilder.zenToolbarElementBackground(scheme: scheme)
        let fieldBackgroundHover = ThemeChromeRecipeBuilder.zenToolbarElementHoverBackground(
            elementBackground: fieldBackground,
            scheme: scheme
        )
        let floatingSurfaceBackground = ThemeChromeRecipeBuilder
            .floatingSurfaceBackground(scheme: scheme)
        let floatingSurfaceBorder = ThemeChromeRecipeBuilder
            .floatingSurfaceBorder(scheme: scheme)
        let floatingSurfaceSecondaryBackground = ThemeChromeRecipeBuilder
            .floatingSurfaceSecondaryBackground(scheme: scheme)
        let floatingSurfaceSelection = ThemeChromeRecipeBuilder
            .floatingSurfaceSelection(scheme: scheme)
        let floatingSurfaceHover = ThemeChromeRecipeBuilder
            .floatingSurfaceHover(scheme: scheme)
        let sidebarRowActive: Color = {
            switch scheme {
            case .light:
                return ThemeChromeRecipeColors.Sidebar.activeLight
            case .dark:
                return ThemeChromeRecipeColors.Sidebar.activeDark
            @unknown default:
                return ThemeChromeRecipeColors.Sidebar.activeFallback
            }
        }()
        let sidebarRowHover: Color = {
            switch scheme {
            case .light:
                return ThemeChromeRecipeColors.Sidebar.hoverLight
            case .dark:
                return ThemeChromeRecipeColors.Sidebar.hoverDark
            @unknown default:
                return ThemeChromeRecipeColors.Sidebar.hoverFallback
            }
        }()
        let sidebarSelectionShadow: Color = {
            switch scheme {
            case .light:
                return ThemeChromeRecipeColors.Sidebar.selectionShadowLight
            case .dark:
                return ThemeChromeRecipeColors.Sidebar.selectionShadowDark
            @unknown default:
                return ThemeChromeRecipeColors.Sidebar.selectionShadowFallback
            }
        }()

        let separator: Color = {
            switch scheme {
            case .light:
                return ThemeChromeRecipeColors.Sidebar.separatorLight
            case .dark:
                return ThemeChromeRecipeColors.Sidebar.separatorDark
            @unknown default:
                return ThemeChromeRecipeColors.Sidebar.separatorFallback
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
            chromeNavigationControlDisabledAlpha: chromeNavigationControlDisabledAlpha,
            popoverActionDisabledAlpha: popoverActionDisabledAlpha,
            sidebarRowActive: sidebarRowActive,
            sidebarRowHover: sidebarRowHover,
            sidebarSelectionShadow: sidebarSelectionShadow,
            // Match selected tab rows (`SpaceTab`, `SplitGroupSidebarRow`): white lift when the live tab is this favorite.
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
            floatingSurfaceBackground: floatingSurfaceBackground,
            floatingSurfaceBorder: floatingSurfaceBorder,
            floatingSurfaceSecondaryBackground: floatingSurfaceSecondaryBackground,
            floatingSurfaceSelection: floatingSurfaceSelection,
            floatingSurfaceHover: floatingSurfaceHover
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
            chromeNavigationControlDisabledAlpha: chromeNavigationControlDisabledAlpha + (other.chromeNavigationControlDisabledAlpha - chromeNavigationControlDisabledAlpha) * CGFloat(clamped),
            popoverActionDisabledAlpha: popoverActionDisabledAlpha + (other.popoverActionDisabledAlpha - popoverActionDisabledAlpha) * CGFloat(clamped),
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
            floatingSurfaceBackground: mix(floatingSurfaceBackground, other.floatingSurfaceBackground),
            floatingSurfaceBorder: mix(floatingSurfaceBorder, other.floatingSurfaceBorder),
            floatingSurfaceSecondaryBackground: mix(floatingSurfaceSecondaryBackground, other.floatingSurfaceSecondaryBackground),
            floatingSurfaceSelection: mix(floatingSurfaceSelection, other.floatingSurfaceSelection),
            floatingSurfaceHover: mix(floatingSurfaceHover, other.floatingSurfaceHover)
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
            chromeNavigationControlDisabledAlpha: chromeNavigationControlDisabledAlpha,
            popoverActionDisabledAlpha: popoverActionDisabledAlpha,
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
            floatingSurfaceBackground: floatingSurfaceBackground,
            floatingSurfaceBorder: floatingSurfaceBorder,
            floatingSurfaceSecondaryBackground: floatingSurfaceSecondaryBackground,
            floatingSurfaceSelection: floatingSurfaceSelection,
            floatingSurfaceHover: floatingSurfaceHover
        )
    }
}
