import SwiftUI

struct FloatingBarChromeHost: View {
    @ObservedObject var browserManager: BrowserManager
    var windowState: BrowserWindowState
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var colorScheme: ColorScheme
    var isPresented: Bool

    var body: some View {
        Group {
            if isPresented {
                FloatingBarView()
                    .environmentObject(browserManager)
                    .environment(windowState)
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
