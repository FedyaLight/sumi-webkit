import SwiftUI

struct CommandPaletteChromeHost: View {
    var browserContext: CommandPaletteBrowserContext
    var windowState: BrowserWindowState
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var colorScheme: ColorScheme
    var isPresented: Bool

    var body: some View {
        Group {
            if isPresented {
                CommandPaletteView(browserContext: browserContext)
                    .environment(windowState)
                    .environment(\.sumiSettings, sumiSettings)
                    .sumiChromeThemeScope(
                        context: resolvedThemeContext,
                        settings: sumiSettings
                    )
                    .environment(\.colorScheme, colorScheme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(isPresented)
    }
}
