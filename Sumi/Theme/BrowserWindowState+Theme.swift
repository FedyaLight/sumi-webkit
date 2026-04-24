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

#if DEBUG
struct SidebarThemeResolutionSnapshot: Equatable {
    let workspacePrimaryHex: String
    let sourceWorkspacePrimaryHex: String
    let targetWorkspacePrimaryHex: String
    let chromeColorScheme: ColorScheme
    let sourceChromeColorScheme: ColorScheme
    let targetChromeColorScheme: ColorScheme
    let chromeDarknessProgress: Double
    let transitionProgress: Double

    init(context: ResolvedThemeContext) {
        workspacePrimaryHex = context.workspaceTheme.gradient.primaryColorHex
        sourceWorkspacePrimaryHex = context.sourceWorkspaceTheme.gradient.primaryColorHex
        targetWorkspacePrimaryHex = context.targetWorkspaceTheme.gradient.primaryColorHex
        chromeColorScheme = context.chromeColorScheme
        sourceChromeColorScheme = context.sourceChromeColorScheme
        targetChromeColorScheme = context.targetChromeColorScheme
        chromeDarknessProgress = context.chromeDarknessProgress
        transitionProgress = context.transitionProgress
    }

    @MainActor
    static func make(
        windowState: BrowserWindowState,
        settings: SumiSettingsService,
        globalColorScheme: ColorScheme
    ) -> SidebarThemeResolutionSnapshot {
        SidebarThemeResolutionSnapshot(
            context: windowState.resolvedThemeContext(
                global: globalColorScheme,
                settings: settings
            )
        )
    }
}
#endif
