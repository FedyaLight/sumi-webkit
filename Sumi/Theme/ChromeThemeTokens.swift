import AppKit
import SumiDomain
import SwiftUI

/// SwiftUI color recipe for browser chrome. Non-color spacing/metrics live in
/// `ChromeLayoutTokens` owns numeric layout metrics; this type owns colors.
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

enum ChromeThemeTypography {
    static let floatingBarInput = Font.system(size: 13, weight: .semibold)
    static var floatingBarInputNSFont: NSFont { NSFont.systemFont(ofSize: 13, weight: .semibold) }
    static let floatingBarLeadingIcon = Font.system(size: 13, weight: .regular)
    static let floatingBarToken = Font.system(size: 13, weight: .semibold)
    static let floatingBarMicroLabel = Font.system(size: 11, weight: .semibold)
    static let floatingBarSuggestionRow = Font.system(size: 13, weight: .semibold)
    static var floatingBarSuggestionRowNSFont: NSFont { NSFont.systemFont(ofSize: 13, weight: .semibold) }
    static let floatingBarSuggestionAction = Font.system(size: 12, weight: .medium)
    static let floatingBarSuggestionChip = Font.system(size: 10, weight: .semibold)
    static let floatingBarSuggestionControl = Font.system(size: 13, weight: .semibold)
    static let floatingBarDeleteControlSmall = Font.system(size: 10, weight: .bold)
    static let floatingBarDeleteControl = Font.system(size: 11, weight: .bold)
    static let floatingBarDeleteAction = Font.system(size: 11, weight: .semibold)
}

enum ThemeChromeRecipeColors {
    enum Foreground {
        static let preferredLight = Color.white.opacity(0.96)
        static let preferredDark = Color.black.opacity(0.88)
        static let primaryLight = Color.black.opacity(0.84)
        static let primaryDark = Color.white.opacity(0.92)
        static let primaryFallback = Color.primary
        static let secondaryLight = Color.black.opacity(0.56)
        static let secondaryDark = Color.white.opacity(0.68)
        static let secondaryFallback = Color.secondary
        static let tertiaryLight = Color.black.opacity(0.38)
        static let tertiaryDark = Color.white.opacity(0.46)
        static let tertiaryFallback = Color.secondary.opacity(0.6)
    }

    enum Sidebar {
        static let activeLight = Color.white.opacity(0.85)
        static let activeDark = Color.white.opacity(0.18)
        static let activeFallback = Color.white.opacity(0.2)
        static let hoverLight = Color.black.opacity(0.08)
        static let hoverDark = Color.white.opacity(0.10)
        static let hoverFallback = Color.primary.opacity(0.1)
        static let selectionShadowLight = Color.black.opacity(0.15)
        static let selectionShadowDark = Color.black.opacity(0.05)
        static let selectionShadowFallback = Color.black.opacity(0.08)
        static let separatorLight = Color.black.opacity(0.12)
        static let separatorDark = Color.white.opacity(0.26)
        static let separatorFallback = Color.primary.opacity(0.14)
    }

    enum Neutral {
        static let lightBackground = Color.white
        static let darkDefaultBackground = Color(hex: "12151A")
        static let darkNightBackground = Color(hex: "0C1015")
        static let darkColorfulBackground = Color(hex: "151A24")
        static let elevatedDarkOverlay = Color.white.opacity(0.28)
        static let toolbarLight = Color.black.opacity(0.08)
        static let toolbarDark = Color.white.opacity(0.12)
        static let toolbarFallback = Color.black.opacity(0.08)
        static let toolbarHoverLight = Color.black.opacity(0.08)
        static let toolbarHoverDark = Color.white.opacity(0.10)
        static let toolbarHoverFallback = Color.black.opacity(0.08)
    }

    enum FloatingBar {
        static let backgroundLight = Color.white
        static let backgroundDark = Color(hex: "1C1C1E")
        static let backgroundFallback = Color.white
        static let chipLight = Color.black.opacity(0.06)
        static let chipDark = Color.white.opacity(0.10)
        static let chipFallback = Color.black.opacity(0.06)
        static let selectedRowLight = Color.black.opacity(0.08)
        static let selectedRowDark = Color.white.opacity(0.14)
        static let selectedRowFallback = Color.black.opacity(0.08)
        static let hoverRowLight = Color.black.opacity(0.05)
        static let hoverRowDark = Color.white.opacity(0.08)
        static let hoverRowFallback = Color.black.opacity(0.05)
    }
}

enum SumiButtonThemeTokens {
    enum Colors {
        static let destructiveBackground = Color.red
    }
}

enum FloatingBarThemeTokens {
    enum Colors {
        static let deleteConfirmationForeground = Color.white
        static let reducedTransparencyShadow = Color.black.opacity(0.165)
        static let localVignetteLightShadow = Color.black.opacity(0.16)
        static let localVignetteDarkShadow = Color.black.opacity(0.30)
        static let localVignetteFallbackShadow = Color.black.opacity(0.14)
    }
}

enum ChromePageLoadingIndicatorStyle {
    private static let contrastBlendAmount: CGFloat = 0.65

    static func fillColor(
        tokens: ChromeThemeTokens,
        workspaceTheme: WorkspaceTheme,
        fallbackColorScheme: ColorScheme
    ) -> Color {
        Color(nsColor: fillColor(
            accentColor: nsColor(tokens.accent),
            isDarkTheme: isDarkTheme(
                workspaceTheme: workspaceTheme,
                fallbackColorScheme: fallbackColorScheme
            )
        ))
    }

    static func fillColor(accentColor: NSColor, isDarkTheme: Bool) -> NSColor {
        let contrastColor: NSColor = isDarkTheme ? .white : .black
        return accentColor.blended(withFraction: contrastBlendAmount, of: contrastColor) ?? contrastColor
    }

    static func isDarkTheme(
        workspaceTheme: WorkspaceTheme,
        fallbackColorScheme: ColorScheme
    ) -> Bool {
        guard !workspaceTheme.gradientTheme.normalizedColors.isEmpty else {
            return fallbackColorScheme == .dark
        }

        return NSColor(Color(hex: workspaceTheme.gradientTheme.primaryColorHex))
            .themePerceivedLightness < 0.5
    }

    private static func nsColor(_ color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.displayP3)
            ?? NSColor(color).usingColorSpace(.sRGB)
            ?? .controlAccentColor
    }
}

enum ChromeThemeColorSchemeKey: Hashable {
    case light
    case dark
    case unknown

    init(_ colorScheme: ColorScheme) {
        switch colorScheme {
        case .light: self = .light
        case .dark: self = .dark
        @unknown default: self = .unknown
        }
    }
}

struct ChromeThemeRecipeKey: Hashable {
    let sourceWorkspaceTheme: WorkspaceTheme
    let targetWorkspaceTheme: WorkspaceTheme
    let sourceColorScheme: ChromeThemeColorSchemeKey
    let targetColorScheme: ChromeThemeColorSchemeKey
    let settingsFingerprint: Int

    init(context: ResolvedThemeContext, settingsFingerprint: Int) {
        sourceWorkspaceTheme = context.sourceWorkspaceTheme
        targetWorkspaceTheme = context.targetWorkspaceTheme
        sourceColorScheme = ChromeThemeColorSchemeKey(context.sourceChromeColorScheme)
        targetColorScheme = ChromeThemeColorSchemeKey(context.targetChromeColorScheme)
        self.settingsFingerprint = settingsFingerprint
    }
}

@MainActor
private enum ChromeThemeRecipeMemo {
    private struct Entry {
        var recipe: ChromeThemeRecipe
        var lastAccess: UInt64
    }

    private static let capacity = 32
    private static var entries: [ChromeThemeRecipeKey: Entry] = [:]
    private static var accessCounter: UInt64 = 0

    static func recipe(for key: ChromeThemeRecipeKey) -> ChromeThemeRecipe? {
        guard var entry = entries[key] else { return nil }
        accessCounter &+= 1
        entry.lastAccess = accessCounter
        entries[key] = entry
        return entry.recipe
    }

    static func store(_ recipe: ChromeThemeRecipe, for key: ChromeThemeRecipeKey) {
        accessCounter &+= 1
        entries[key] = Entry(recipe: recipe, lastAccess: accessCounter)
        guard entries.count > capacity,
              let leastRecentKey = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key
        else { return }
        entries.removeValue(forKey: leastRecentKey)
    }

    #if DEBUG
        static func resetForTests() {
            entries.removeAll()
            accessCounter = 0
        }
    #endif
}

@MainActor
private enum ChromeThemeTokenMemo {
    private static var context: ResolvedThemeContext?
    private static var settingsFingerprint: Int?
    private static var tokens: ChromeThemeTokens?

    static func value(
        context candidateContext: ResolvedThemeContext,
        settingsFingerprint candidateFingerprint: Int
    ) -> ChromeThemeTokens? {
        guard context == candidateContext,
              settingsFingerprint == candidateFingerprint
        else { return nil }
        return tokens
    }

    static func store(
        _ candidateTokens: ChromeThemeTokens,
        context candidateContext: ResolvedThemeContext,
        settingsFingerprint candidateFingerprint: Int
    ) {
        context = candidateContext
        settingsFingerprint = candidateFingerprint
        tokens = candidateTokens
    }

    #if DEBUG
        static func resetForTests() {
            context = nil
            settingsFingerprint = nil
            tokens = nil
        }
    #endif
}

#if DEBUG
    @MainActor
    enum ChromeThemeCacheDiagnostics {
        static func resetForTests() {
            ChromeThemeRecipeMemo.resetForTests()
            ChromeThemeTokenMemo.resetForTests()
            ThemeChromeRecipeBuilder.recipeBuildCountForTests = 0
        }
    }
#endif

@MainActor
extension ResolvedThemeContext {
    func tokens(settings: SumiSettingsService) -> ChromeThemeTokens {
        let fingerprint = settings.chromeTokenRecipeFingerprint
        if let tokens = ChromeThemeTokenMemo.value(
            context: self,
            settingsFingerprint: fingerprint
        ) {
            return tokens
        }

        let recipeKey = ChromeThemeRecipeKey(
            context: self,
            settingsFingerprint: fingerprint
        )
        let recipe: ChromeThemeRecipe
        if let cachedRecipe = ChromeThemeRecipeMemo.recipe(for: recipeKey) {
            recipe = cachedRecipe
        } else {
            recipe = ThemeChromeRecipeBuilder.makeRecipe(context: self, settings: settings)
            ChromeThemeRecipeMemo.store(recipe, for: recipeKey)
        }

        let usesTransition = sourceChromeColorScheme != targetChromeColorScheme
            || sourceWorkspaceTheme != targetWorkspaceTheme
            || transitionProgress < 1
        let tokens = recipe.tokens(
            progress: transitionProgress,
            usesTransition: usesTransition
        )
        ChromeThemeTokenMemo.store(
            tokens,
            context: self,
            settingsFingerprint: fingerprint
        )
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

private struct ChromeThemeTokensKey: EnvironmentKey {
    static let defaultValue: ChromeThemeTokens? = nil
}

extension EnvironmentValues {
    var chromeThemeTokens: ChromeThemeTokens? {
        get { self[ChromeThemeTokensKey.self] }
        set { self[ChromeThemeTokensKey.self] = newValue }
    }
}

@MainActor
extension View {
    func sumiChromeThemeScope(
        context: ResolvedThemeContext,
        settings: SumiSettingsService
    ) -> some View {
        environment(\.resolvedThemeContext, context)
            .environment(\.chromeThemeTokens, context.tokens(settings: settings))
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
