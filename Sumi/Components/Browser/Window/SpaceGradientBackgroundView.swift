import SwiftUI

// Dithered gradient rendering
import CoreGraphics

enum SpaceGradientBackgroundSurface {
    case browser
    case toolbarChrome
}

// Renders the current space's gradient as a bottom background layer.
// Zen reference: `ZenGradientGenerator.getGradient` resolves workspace colors and opacity separately from `color-scheme`.
struct SpaceGradientBackgroundView: View {
    var surface: SpaceGradientBackgroundSurface = .browser

    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings

    private var chromeTokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var activeResolution: ZenWorkspaceThemeResolution {
        resolvedTheme(themeContext.workspaceTheme)
    }

    private var sourceResolution: ZenWorkspaceThemeResolution {
        resolvedTheme(themeContext.sourceWorkspaceTheme)
    }

    private var targetResolution: ZenWorkspaceThemeResolution {
        resolvedTheme(themeContext.targetWorkspaceTheme)
    }

    private var transitionProgress: Double {
        min(max(themeContext.transitionProgress, 0), 1)
    }

    private var usesResolvedTransitionLayers: Bool {
        themeContext.isInteractiveTransition
            || !themeContext.sourceWorkspaceTheme.visuallyEquals(themeContext.targetWorkspaceTheme)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                chromeTokens.windowBackground

                if usesResolvedTransitionLayers {
                    gradientVisualLayer(for: gradient(from: sourceResolution), size: proxy.size)
                        .opacity(1 - transitionProgress)
                    gradientVisualLayer(for: gradient(from: targetResolution), size: proxy.size)
                        .opacity(transitionProgress)
                } else {
                    gradientVisualLayer(for: gradient(from: activeResolution), size: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gradientVisualLayer(for gradient: SpaceGradient, size: CGSize) -> some View {
        ZStack {
            BarycentricGradientView(gradient: gradient)
                .opacity(max(0, min(1, gradient.opacity)))
                .frame(width: size.width, height: size.height)
                .clipped()
                .allowsHitTesting(false)
            TiledNoiseTexture(opacity: max(0, min(1, gradient.grain)))
                .frame(width: size.width, height: size.height)
                .clipped()
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func resolvedTheme(_ theme: WorkspaceTheme) -> ZenWorkspaceThemeResolution {
        ZenWorkspaceThemeResolver.resolve(
            theme: theme,
            globalWindowScheme: themeContext.globalColorScheme,
            settings: sumiSettings
        )
    }

    private func gradient(from resolution: ZenWorkspaceThemeResolution) -> SpaceGradient {
        switch surface {
        case .browser:
            return resolution.backgroundGradient
        case .toolbarChrome:
            return resolution.toolbarGradient
        }
    }
}
