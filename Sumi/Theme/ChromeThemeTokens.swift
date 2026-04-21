import AppKit
import SwiftUI

struct ChromeThemeTokens {
    let accent: Color
    let background: Color
    let toolbarBackground: Color
    let fieldBackground: Color
    let fieldBackgroundHover: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let sidebarRowActive: Color
    let sidebarRowHover: Color
    let sidebarSelectionShadow: Color
    let pinnedActiveBackground: Color
    let pinnedHoverBackground: Color
    let pinnedIdleBackground: Color
    let separator: Color
    let dropGuide: Color
    let dropGuideBackground: Color
    /// Neutral lift from the chrome base (`elevatedNeutral`): sidebars, peek-adjacent chrome, in-flow menu panels (e.g. sidebar history strip). Not for floating command/hub-style surfaces.
    let panelBackground: Color
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
    /// Opaque floating surface (command palette, URL hub/identity popovers, theme picker, modal peek cards). Flat white / near-black — not the same as ``panelBackground``.
    let commandPaletteBackground: Color
    /// Secondary fills inside the palette (e.g. “Tab” chip, favicon wells).
    let commandPaletteChipBackground: Color
    let commandPaletteRowSelected: Color
    let commandPaletteRowHover: Color
}

@MainActor
extension ResolvedThemeContext {
    func tokens(settings: SumiSettingsService) -> ChromeThemeTokens {
        ThemeChromeRecipeBuilder.makeTokens(
            context: self,
            settings: settings
        )
    }
}

extension SumiSettingsService {
    /// Stable-ish hash of inputs that affect `ThemeChromeRecipeBuilder.makeTokens` besides `ResolvedThemeContext`.
    /// Used to avoid re-painting AppKit find chrome when nothing relevant changed.
    var chromeTokenRecipeFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(themeUseSystemColors)
        hasher.combine(themeStyledStatusPanel)
        hasher.combine(darkThemeStyle)
        hasher.combine(Self.systemControlAccentFingerprint)
        return hasher.finalize()
    }

    private static var systemControlAccentFingerprint: Int {
        let c = NSColor.controlAccentColor
        guard let rgb = c.usingColorSpace(.displayP3) ?? c.usingColorSpace(.sRGB) else { return 0 }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        var hasher = Hasher()
        hasher.combine(r)
        hasher.combine(g)
        hasher.combine(b)
        hasher.combine(a)
        return hasher.finalize()
    }
}
