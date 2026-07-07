import AppKit
import SwiftUI

extension View {
    /// Pins native chrome surface content (popover, sheet, panel) to the space's
    /// resolved lightness from the theme picker (auto/light/dark).
    ///
    /// Requires `\.resolvedThemeContext` to be set upstream: the environment
    /// default is dark, so bare `NSHostingController` hierarchies must inject the
    /// context before using this (see `SumiBoostEditorPanelController`).
    func sumiNativeSurfaceColorScheme() -> some View {
        modifier(SumiNativeSurfaceColorSchemeModifier())
    }

    /// Explicit variant for AppKit presenters that resolve the scheme before
    /// hosting SwiftUI content (NSPopover presenters).
    func sumiNativeSurfaceColorScheme(
        _ scheme: ColorScheme,
        themeContext: ResolvedThemeContext
    ) -> some View {
        environment(\.resolvedThemeContext, themeContext)
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(scheme)
    }
}

private struct SumiNativeSurfaceColorSchemeModifier: ViewModifier {
    @Environment(\.resolvedThemeContext) private var themeContext

    func body(content: Content) -> some View {
        let scheme = themeContext.nativeSurfaceColorScheme
        content
            .environment(\.resolvedThemeContext, themeContext.nativeSurfaceThemeContext)
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(scheme)
    }
}

@MainActor
extension NSAlert {
    /// Pins the alert window to the space lightness. No-op when the window
    /// state or settings are unavailable (the alert stays on the system
    /// appearance).
    func sumiApplyNativeSurfaceAppearance(
        windowState: BrowserWindowState?,
        settings: SumiSettingsService?
    ) {
        guard let windowState, let settings else { return }
        window.appearance = windowState.nativeSurfaceAppearance(settings: settings)
    }

    /// Variant for call sites that already hold a resolved theme context.
    func sumiApplyNativeSurfaceAppearance(themeContext: ResolvedThemeContext?) {
        guard let themeContext else { return }
        window.appearance = NSAppearance.sumiChromeAppearance(
            for: themeContext.nativeSurfaceColorScheme,
            fallback: window.appearance
        )
    }
}

@MainActor
extension BrowserWindowState {
    /// Canonical global window scheme: Settings ▸ window-scheme override when
    /// set, otherwise the window's (or app's) effective appearance.
    func globalColorScheme(settings: SumiSettingsService) -> ColorScheme {
        switch settings.windowSchemeMode {
        case .auto:
            let appearance = window?.effectiveAppearance
                ?? NSApplication.shared.effectiveAppearance
            return ColorScheme(sumiChromeAppearance: appearance)
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    /// Space-resolved, transition-stable theme context for native surfaces hung
    /// off this window (popovers, sheets, alerts, panels).
    func nativeSurfaceThemeContext(settings: SumiSettingsService) -> ResolvedThemeContext {
        resolvedThemeContext(
            global: globalColorScheme(settings: settings),
            settings: settings
        )
        .nativeSurfaceThemeContext
    }

    /// Space-resolved NSAppearance for AppKit surfaces (NSPopover, NSMenu,
    /// NSAlert windows, NSPanel).
    func nativeSurfaceAppearance(
        settings: SumiSettingsService,
        fallback: NSAppearance? = nil
    ) -> NSAppearance {
        NSAppearance.sumiChromeAppearance(
            for: nativeSurfaceThemeContext(settings: settings).chromeColorScheme,
            fallback: fallback
        )
    }
}
