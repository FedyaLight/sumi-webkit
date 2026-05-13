import SwiftUI

struct FindInPageChromeHost: View {
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject var findManager: FindManager
    var windowRegistry: WindowRegistry
    var windowState: BrowserWindowState
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var colorScheme: ColorScheme

    private var shouldPresent: Bool {
        windowRegistry.activeWindow?.id == windowState.id
            && findManager.isFindBarVisible
            && !isModalSuppressed
    }

    private var isModalSuppressed: Bool {
        browserManager.dialogManager.isPresented(in: windowState.window)
    }

    var body: some View {
        FindInPageChromeHitTestingWrapper(
            findManager: findManager,
            windowStateID: windowState.id,
            themeContext: resolvedThemeContext,
            keepsChromeMounted: shouldPresent,
            isInteractive: shouldPresent
        )
        .environmentObject(browserManager)
        .environment(windowRegistry)
        .environment(\.sumiSettings, sumiSettings)
        .environment(\.resolvedThemeContext, resolvedThemeContext)
        .environment(\.colorScheme, colorScheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(shouldPresent)
    }
}
