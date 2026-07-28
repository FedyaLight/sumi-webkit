import SwiftUI

struct FindInPageChromePresentation: Equatable {
    let isPresented: Bool

    init(
        isActiveWindow: Bool,
        isFindBarVisible: Bool,
        isModalSuppressed: Bool,
        isPlacementSuppressed: Bool
    ) {
        isPresented = isActiveWindow
            && isFindBarVisible
            && !isModalSuppressed
            && !isPlacementSuppressed
    }
}

struct FindInPageChromeHost: View {
    @ObservedObject var findManager: FindManager
    var windowRegistry: WindowRegistry
    var windowState: BrowserWindowState
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var colorScheme: ColorScheme
    var isModalSuppressed: Bool
    var isSuppressed: Bool = false

    private var presentation: FindInPageChromePresentation {
        FindInPageChromePresentation(
            isActiveWindow: windowRegistry.activeWindow?.id == windowState.id,
            isFindBarVisible: findManager.isFindBarVisible,
            isModalSuppressed: isModalSuppressed,
            isPlacementSuppressed: isSuppressed
        )
    }

    var body: some View {
        FindInPageChromeHitTestingWrapper(
            findManager: findManager,
            model: findManager.currentModel,
            focusGeneration: findManager.findFieldFocusGeneration,
            themeContext: resolvedThemeContext,
            isPresented: presentation.isPresented
        )
        .environment(windowRegistry)
        .environment(\.sumiSettings, sumiSettings)
        .sumiChromeThemeScope(
            context: resolvedThemeContext,
            settings: sumiSettings
        )
        .environment(\.colorScheme, colorScheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(presentation.isPresented)
    }
}
