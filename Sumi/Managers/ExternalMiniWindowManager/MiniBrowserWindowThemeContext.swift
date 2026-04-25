import AppKit
import SwiftUI

enum MiniBrowserWindowThemeContextResolver {
    @MainActor
    static func make(
        settings: SumiSettingsService,
        appearance: NSAppearance? = nil
    ) -> ResolvedThemeContext {
        let scheme = colorScheme(
            settings: settings,
            appearance: appearance ?? NSApp.effectiveAppearance
        )
        return ResolvedThemeContext(
            globalColorScheme: scheme,
            chromeColorScheme: scheme,
            sourceChromeColorScheme: scheme,
            targetChromeColorScheme: scheme,
            workspaceTheme: .default,
            sourceWorkspaceTheme: .default,
            targetWorkspaceTheme: .default,
            isInteractiveTransition: false,
            transitionProgress: 1.0
        )
    }

    @MainActor
    private static func colorScheme(
        settings: SumiSettingsService,
        appearance: NSAppearance
    ) -> ColorScheme {
        switch settings.windowSchemeMode {
        case .auto:
            return ColorScheme(miniBrowserEffectiveAppearance: appearance)
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

private extension ColorScheme {
    init(miniBrowserEffectiveAppearance appearance: NSAppearance) {
        let best = appearance.bestMatch(from: [.darkAqua, .aqua])
        self = best == .darkAqua ? .dark : .light
    }
}
