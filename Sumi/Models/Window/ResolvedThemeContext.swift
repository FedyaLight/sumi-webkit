import SwiftUI

struct ResolvedThemeContext: Equatable {
    var globalColorScheme: ColorScheme
    var chromeColorScheme: ColorScheme
    var sourceChromeColorScheme: ColorScheme
    var targetChromeColorScheme: ColorScheme
    var workspaceTheme: WorkspaceTheme
    var sourceWorkspaceTheme: WorkspaceTheme
    var targetWorkspaceTheme: WorkspaceTheme
    var isInteractiveTransition: Bool
    var transitionProgress: Double

    static let `default` = ResolvedThemeContext(
        globalColorScheme: .dark,
        chromeColorScheme: .dark,
        sourceChromeColorScheme: .dark,
        targetChromeColorScheme: .dark,
        workspaceTheme: .default,
        sourceWorkspaceTheme: .default,
        targetWorkspaceTheme: .default,
        isInteractiveTransition: false,
        transitionProgress: 1.0
    )

    var gradient: SpaceGradient {
        workspaceTheme.gradient
    }

    var chromeDarknessProgress: Double {
        let source = sourceChromeColorScheme == .dark ? 1.0 : 0.0
        let target = targetChromeColorScheme == .dark ? 1.0 : 0.0

        if isInteractiveTransition || sourceChromeColorScheme != targetChromeColorScheme {
            return source + (target - source) * transitionProgress
        }

        return chromeColorScheme == .dark ? 1.0 : 0.0
    }
}

private struct ResolvedThemeContextKey: EnvironmentKey {
    static let defaultValue: ResolvedThemeContext = .default
}

extension EnvironmentValues {
    var resolvedThemeContext: ResolvedThemeContext {
        get { self[ResolvedThemeContextKey.self] }
        set { self[ResolvedThemeContextKey.self] = newValue }
    }
}
