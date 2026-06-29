import SwiftUI

struct FindInPageChromeHost: View {
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject var findManager: FindManager
    var windowRegistry: WindowRegistry
    var windowState: BrowserWindowState
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var colorScheme: ColorScheme
    var isSuppressed: Bool = false

    private var shouldPresent: Bool {
        windowRegistry.activeWindow?.id == windowState.id
            && findManager.isFindBarVisible
            && !isModalSuppressed
            && !isSuppressed
    }

    private var isModalSuppressed: Bool {
        browserManager.isNativeModalPresented(in: windowState.id)
    }

    var body: some View {
        FindInPageChromeHitTestingWrapper(
            findManager: findManager,
            windowStateID: windowState.id,
            themeContext: resolvedThemeContext,
            keepsChromeMounted: shouldPresent,
            isInteractive: shouldPresent
        )
        .environment(windowRegistry)
        .environment(\.sumiSettings, sumiSettings)
        .environment(\.resolvedThemeContext, resolvedThemeContext)
        .environment(\.colorScheme, colorScheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(shouldPresent)
    }
}
