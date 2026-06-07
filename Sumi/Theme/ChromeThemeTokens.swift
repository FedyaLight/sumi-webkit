import AppKit
import SwiftUI

struct ChromeThemeTokens {
    let accent: Color
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
    /// Opaque floating surface (floating bar, URL hub/identity popovers, theme picker, modal glance cards). Flat white / near-black.
    let floatingBarBackground: Color
    /// Secondary fills inside the palette (e.g. “Tab” chip, favicon wells).
    let floatingBarChipBackground: Color
    let floatingBarRowSelected: Color
    let floatingBarRowHover: Color
}

private struct ChromeThemeTokenRecipeKey: Equatable {
    let context: ResolvedThemeContext
    let settingsFingerprint: Int

    static func == (lhs: ChromeThemeTokenRecipeKey, rhs: ChromeThemeTokenRecipeKey) -> Bool {
        lhs.context == rhs.context
            && lhs.settingsFingerprint == rhs.settingsFingerprint
    }
}

@MainActor
private enum ChromeThemeTokenMemo {
    private struct Entry {
        var key: ChromeThemeTokenRecipeKey
        var tokens: ChromeThemeTokens
    }

    private static let capacity = 8
    private static var entries: [Entry] = []

    static func tokens(for key: ChromeThemeTokenRecipeKey) -> ChromeThemeTokens? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else {
            return nil
        }

        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        return entry.tokens
    }

    static func store(_ tokens: ChromeThemeTokens, for key: ChromeThemeTokenRecipeKey) {
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries.remove(at: index)
        }

        entries.insert(Entry(key: key, tokens: tokens), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }
}

@MainActor
extension ResolvedThemeContext {
    func tokens(settings: SumiSettingsService) -> ChromeThemeTokens {
        let key = ChromeThemeTokenRecipeKey(
            context: self,
            settingsFingerprint: settings.chromeTokenRecipeFingerprint
        )
        if let tokens = ChromeThemeTokenMemo.tokens(for: key) {
            return tokens
        }

        let tokens = ThemeChromeRecipeBuilder.makeTokens(
            context: self,
            settings: settings
        )
        ChromeThemeTokenMemo.store(tokens, for: key)
        return tokens
    }

    var nativeSurfaceColorScheme: ColorScheme {
        let usesTransition = isInteractiveTransition || sourceWorkspaceTheme != targetWorkspaceTheme
        if usesTransition {
            return transitionProgress < 0.5 ? sourceChromeColorScheme : targetChromeColorScheme
        }
        return chromeColorScheme
    }

    var nativeSurfaceThemeContext: ResolvedThemeContext {
        let scheme = nativeSurfaceColorScheme
        var context = self
        context.globalColorScheme = scheme
        context.chromeColorScheme = scheme
        context.sourceChromeColorScheme = scheme
        context.targetChromeColorScheme = scheme
        context.isInteractiveTransition = false
        context.transitionProgress = 1
        return context
    }

    var nativeSurfaceSelectionBackground: Color {
        switch nativeSurfaceColorScheme {
        case .light:
            return Color.black.opacity(0.10)
        case .dark:
            return Color.white.opacity(0.16)
        @unknown default:
            return Color.primary.opacity(0.12)
        }
    }
}

extension SumiSettingsService {
    /// Stable-ish hash of inputs that affect `ThemeChromeRecipeBuilder.makeTokens` besides `ResolvedThemeContext`.
    /// Used to avoid re-painting AppKit find chrome when nothing relevant changed.
    var chromeTokenRecipeFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(themeUseSystemColors)
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
