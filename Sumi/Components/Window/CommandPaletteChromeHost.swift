import SwiftUI

struct CommandPaletteChromeHost: View {
    @ObservedObject var browserManager: BrowserManager
    var windowState: BrowserWindowState
    var commandPalette: CommandPalette
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var colorScheme: ColorScheme
    var isPresented: Bool

    var body: some View {
        Group {
            if isPresented {
                CommandPaletteView()
                    .environmentObject(browserManager)
                    .environment(windowState)
                    .environment(commandPalette)
                    .environment(\.sumiSettings, sumiSettings)
                    .environment(\.resolvedThemeContext, resolvedThemeContext)
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
