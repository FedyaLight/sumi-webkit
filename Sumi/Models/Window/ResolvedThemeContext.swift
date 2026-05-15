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

    var rendersCustomChromeTheme: Bool {
        workspaceTheme.gradientTheme.usesCustomChromeTheme
            || sourceWorkspaceTheme.gradientTheme.usesCustomChromeTheme
            || targetWorkspaceTheme.gradientTheme.usesCustomChromeTheme
    }

    var activeCustomChromeThemeIntensity: Double {
        workspaceTheme.gradientTheme.customChromeThemeIntensity
    }

    var sourceCustomChromeThemeIntensity: Double {
        sourceWorkspaceTheme.gradientTheme.customChromeThemeIntensity
    }

    var targetCustomChromeThemeIntensity: Double {
        targetWorkspaceTheme.gradientTheme.customChromeThemeIntensity
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
