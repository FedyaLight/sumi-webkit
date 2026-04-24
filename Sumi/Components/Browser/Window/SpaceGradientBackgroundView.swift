import SwiftUI

// Dithered gradient rendering
import CoreGraphics

// Renders the current space's gradient as a bottom background layer.
// Zen reference: workspace tint is a small fraction of a near-neutral base (e.g. `color-mix(..., rgb(24,24,24) 96%, var(--zen-primary-color))` in zen-glance.css, urlbar `hsl(0,0%,6.7%)` mix in zen-omnibox.css). We keep `chromeDarknessProgress` as the driver so sidebar text contrast stays aligned with `ThemeContrastResolver`.
struct SpaceGradientBackgroundView: View {
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings

    private var gradient: SpaceGradient {
        themeContext.gradient
    }

    private var chromeTokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var chromeDarknessProgress: Double {
        themeContext.chromeDarknessProgress
    }

    private var sourceGradient: SpaceGradient {
        themeContext.sourceWorkspaceTheme.gradient
    }

    private var targetGradient: SpaceGradient {
        themeContext.targetWorkspaceTheme.gradient
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
                chromeTokens.windowBackground.opacity(baseBackgroundOpacity(for: gradient))

                if usesResolvedTransitionLayers {
                    gradientVisualLayer(for: sourceGradient, size: proxy.size)
                        .opacity(1 - transitionProgress)
                    gradientVisualLayer(for: targetGradient, size: proxy.size)
                        .opacity(transitionProgress)
                } else {
                    gradientVisualLayer(for: gradient, size: proxy.size)
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
                .opacity(gradientLayerOpacity(for: gradient))
                .frame(width: size.width, height: size.height)
                .clipped()
                .allowsHitTesting(false)
            themeOverlay(for: gradient)
                .frame(width: size.width, height: size.height)
                .clipped()
            TiledNoiseTexture(opacity: max(0, min(1, gradient.grain)))
                .frame(width: size.width, height: size.height)
                .clipped()
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func baseBackgroundOpacity(for gradient: SpaceGradient) -> Double {
        let lightOpacity = 0.2
        // Slightly stronger anchor in dark chrome so the stack stays charcoal even with vivid workspace hues.
        let darkOpacity = max(0.18, 0.28 - gradient.opacity * 0.07)
        return lightOpacity + (darkOpacity - lightOpacity) * chromeDarknessProgress
    }

    private func gradientLayerOpacity(for gradient: SpaceGradient) -> Double {
        let clampedOpacity = max(0.0, min(1.0, gradient.opacity))
        let lightOpacity = clampedOpacity * 0.34
        // Zen keeps chroma mostly as a tint; ~0.76 let bright stops wash the sidebar in dark mode.
        let darkOpacity = clampedOpacity * 0.52
        return lightOpacity + (darkOpacity - lightOpacity) * chromeDarknessProgress
    }

    @ViewBuilder
    private func themeOverlay(for _: SpaceGradient) -> some View {
        ZStack {
            Color.white.opacity(0.18 * (1 - chromeDarknessProgress))
            Color.black.opacity(0.30 * chromeDarknessProgress)
            // Nudge composite toward Zen’s ~rgb(24,24,24) neutral without a second full-opacity pass.
            Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255)
                .opacity(0.07 * chromeDarknessProgress)
        }
    }
}
