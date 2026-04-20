import SwiftUI

@MainActor
extension BrowserWindowState {
    var workspaceTheme: WorkspaceTheme {
        if isIncognito {
            return .incognito
        }
        return windowThemeState.resolvedTheme
    }

    /// Convenience surface for views that still render directly from a gradient.
    var gradient: SpaceGradient {
        workspaceTheme.gradient
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

    var isThemeTransitioning: Bool {
        get { windowThemeState.isTransitioning }
        set {
            guard !newValue else { return }
            if !windowThemeState.isInteractive {
                windowThemeState.mode = .idle
            }
        }
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
        let sourceThemeValue = previousWorkspaceTheme ?? resolvedWorkspaceTheme
        let targetThemeValue = targetWorkspaceTheme ?? resolvedWorkspaceTheme
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
            isInteractiveTransition: isInteractiveSpaceTransition,
            transitionProgress: themeTransitionProgress
        )
    }
}
