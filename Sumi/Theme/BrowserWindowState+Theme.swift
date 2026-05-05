import SwiftUI

@MainActor
extension BrowserWindowState {
    var workspaceTheme: WorkspaceTheme {
        if isIncognito {
            return .incognito
        }
        return windowThemeState.resolvedTheme
    }

    var displayedWorkspaceTheme: WorkspaceTheme {
        get { windowThemeState.committedTheme }
        set { windowThemeState.committedTheme = newValue }
    }

    var previousWorkspaceTheme: WorkspaceTheme? {
        get { windowThemeState.sourceTheme }
        set { windowThemeState.sourceTheme = newValue }
    }

    var targetWorkspaceTheme: WorkspaceTheme? {
        get { windowThemeState.targetTheme }
        set { windowThemeState.targetTheme = newValue }
    }

    var themeTransitionProgress: Double {
        get { windowThemeState.progress }
        set { windowThemeState.progress = newValue }
    }

    var themeTransitionToken: UUID? {
        get { windowThemeState.token }
        set { windowThemeState.token = newValue }
    }

    var spaceTransitionSourceSpaceId: UUID? {
        get { windowThemeState.sourceSpaceId }
        set { windowThemeState.sourceSpaceId = newValue }
    }

    var spaceTransitionDestinationSpaceId: UUID? {
        get { windowThemeState.destinationSpaceId }
        set { windowThemeState.destinationSpaceId = newValue }
    }

    var isInteractiveSpaceTransition: Bool {
        get { windowThemeState.isInteractive }
        set { windowThemeState.mode = newValue ? .interactive : .idle }
    }

    func resolvedThemeContext(
        global globalScheme: ColorScheme,
        settings: SumiSettingsService
    ) -> ResolvedThemeContext {
        let resolvedWorkspaceTheme = workspaceTheme
        let isTransitioning = windowThemeState.isTransitioning
        let sourceThemeValue = isTransitioning
            ? previousWorkspaceTheme ?? resolvedWorkspaceTheme
            : resolvedWorkspaceTheme
        let targetThemeValue = isTransitioning
            ? targetWorkspaceTheme ?? resolvedWorkspaceTheme
            : resolvedWorkspaceTheme
        let transitionProgress = isTransitioning ? themeTransitionProgress : 1.0
        let isInteractiveTransition = isTransitioning && isInteractiveSpaceTransition
        let resolvedChromeScheme = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: resolvedWorkspaceTheme,
            globalWindowScheme: globalScheme,
            settings: settings,
            isIncognito: isIncognito
        )
        let sourceChromeScheme = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: sourceThemeValue,
            globalWindowScheme: globalScheme,
            settings: settings,
            isIncognito: isIncognito
        )
        let targetChromeScheme = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: targetThemeValue,
            globalWindowScheme: globalScheme,
            settings: settings,
            isIncognito: isIncognito
        )

        return ResolvedThemeContext(
            globalColorScheme: globalScheme,
            chromeColorScheme: resolvedChromeScheme,
            sourceChromeColorScheme: sourceChromeScheme,
            targetChromeColorScheme: targetChromeScheme,
            workspaceTheme: resolvedWorkspaceTheme,
            sourceWorkspaceTheme: sourceThemeValue,
            targetWorkspaceTheme: targetThemeValue,
            isInteractiveTransition: isInteractiveTransition,
            transitionProgress: transitionProgress
        )
    }
}
